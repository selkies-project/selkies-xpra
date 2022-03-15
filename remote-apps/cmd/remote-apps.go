package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/gorilla/mux"
	ps "github.com/mitchellh/go-ps"
	remote_apps "selkies.io/remote-apps/pkg"
)

// Wraps server muxer, dynamic map of handlers, and listen port.
type Server struct {
	Dispatcher *mux.Router
	Urls       map[string]func(w http.ResponseWriter, r *http.Request)
	Port       string
}

type StatusResponse struct {
	Code   int         `json:"code"`
	Status string      `json:"status"`
	Data   interface{} `json:"data"`
}

type RemoteAppResponse struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Icon        []byte `json:"icon"`
}

type ListRemoteAppsResponse struct {
	Apps []RemoteAppResponse `json:"apps"`
}

var (
	listenPort  = flag.Int("port", 8842, "port to start service on")
	watchDirArg = flag.String("watch", "/etc/skel/Desktop", "directory containing .desktop files to monitor for changes.")
)

func main() {
	flag.Parse()

	// Muxed server to handle per-app routes.
	server := &Server{
		Port:       fmt.Sprintf("%d", *listenPort),
		Dispatcher: mux.NewRouter(),
		Urls:       make(map[string]func(w http.ResponseWriter, r *http.Request)),
	}

	desktopShortcuts := make(map[string]remote_apps.FreedeskopShortcut, 0)

	// Populate initial list of desktop shortcuts from watch dir.
	matches, err := filepath.Glob(filepath.Join(*watchDirArg, "*.desktop"))
	if err != nil {
		log.Fatal(err)
	}
	for _, srcPath := range matches {
		fds, err := remote_apps.NewFreeDesktopShortcutFromFile(srcPath)
		if err != nil {
			log.Printf("error parsing desktop file: %v", err)
			continue
		}
		appName := fds.DesktopEntry.Fields.Get("Name")
		desktopShortcuts[appName] = fds
		startURL := fmt.Sprintf("/start/%s", appName)
		server.Urls[startURL] = getStartAppHandler(appName, fds)
	}
	log.Printf("INFO: Found %d desktop shortcuts in %s", len(desktopShortcuts), *watchDirArg)
	for name := range desktopShortcuts {
		log.Printf("\t%s", name)
	}

	// Register list apps handler.
	server.Urls["/"] = func(w http.ResponseWriter, r *http.Request) {
		resp := ListRemoteAppsResponse{}
		apps := make([]RemoteAppResponse, 0)
		for name, fds := range desktopShortcuts {
			app := RemoteAppResponse{
				Name:        name,
				Description: fds.DesktopEntry.Fields.Get("Comment"),
				Icon:        fds.DesktopEntry.IconPNGData,
			}
			apps = append(apps, app)
		}
		resp.Apps = apps

		statusCode := http.StatusOK
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(statusCode)
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		enc.Encode(resp)
	}

	desktopFileRE := regexp.MustCompile(".*\\.desktop$")

	// Handle newly created .desktop files.
	var onCreate = func(srcPath string) {
		if !desktopFileRE.MatchString(srcPath) {
			return
		}
		fds, err := remote_apps.NewFreeDesktopShortcutFromFile(srcPath)
		if err != nil {
			log.Printf("[inotify CREATE]: error parsing desktop file: %v", err)
			return
		}
		name := fds.DesktopEntry.Fields.Get("Name")
		desktopShortcuts[name] = fds
		startURL := fmt.Sprintf("/start/%s", name)
		server.Urls[startURL] = getStartAppHandler(name, fds)
		log.Printf("[inotify CREATE]: Added new desktop shortcut: %s: %s", name, fds.Path)
	}

	// Handle removed .desktop files
	var onRemove = func(srcPath string) {
		if !desktopFileRE.MatchString(srcPath) {
			return
		}
		removalName := ""
		for name, fds := range desktopShortcuts {
			if fds.Path == srcPath {
				removalName = name
				break
			}
		}
		if len(removalName) > 0 {
			log.Printf("[inotify REMOVE]: removed desktop file: %s: %s", removalName, srcPath)
			startURL := fmt.Sprintf("/start/%s", removalName)
			delete(server.Urls, startURL)
			delete(desktopShortcuts, removalName)
		}
	}

	// Handle changed .desktop files
	var onChanged = func(srcPath string) {
		if !desktopFileRE.MatchString(srcPath) {
			return
		}
		fds, err := remote_apps.NewFreeDesktopShortcutFromFile(srcPath)
		if err != nil {
			log.Printf("[inotify CHANGED]: error parsing desktop file: %v", err)
			return
		}
		name := fds.DesktopEntry.Fields.Get("Name")
		desktopShortcuts[name] = fds
		startURL := fmt.Sprintf("/start/%s", name)
		server.Urls[startURL] = getStartAppHandler(name, fds)
		log.Printf("[inotify CHANGED]: Updated desktop shortcut: %s: %s", name, fds.Path)
	}

	// Start directory watcher to detect changes in .desktop files.
	watcher, err := remote_apps.StartDirWatcher([]string{*watchDirArg}, onCreate, onChanged, onRemove)
	if err != nil {
		log.Fatal(err)
	}
	defer watcher.Close()

	// Start web server
	log.Printf("INFO: Initializing request routes...\n")
	server.InitDispatch()
	server.Start()
}

func (s *Server) Start() {
	log.Printf("INFO: Starting server on port: %s \n", s.Port)
	http.ListenAndServe(":"+s.Port, s.Dispatcher)
}

func (s *Server) InitDispatch() {
	d := s.Dispatcher
	d.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		writeResponse(w, http.StatusOK, "OK", nil)
	})

	d.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if handler, ok := s.Urls["/"]; ok {
			handler(w, r)
		}
	})

	d.HandleFunc("/start/{appName}", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			writeResponse(w, http.StatusBadRequest, "invalid request method, only POST is supported.", nil)
			return
		}
		vars := mux.Vars(r)
		appName := vars["appName"]
		path := fmt.Sprintf("/start/%s", appName)
		if handler, ok := s.Urls[path]; ok {
			handler(w, r)
		} else {
			writeResponse(w, http.StatusNotFound, fmt.Sprintf("app not found: %s", appName), nil)
		}
	})
}

func getStartAppHandler(appName string, fds remote_apps.FreedeskopShortcut) func(w http.ResponseWriter, r *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		respData := make(map[string]string, 0)
		execStr := prepExecStr(fds.DesktopEntry.Fields.Get("Exec"))
		pid, err := startSubprocess(execStr, nil)
		if err != nil {
			log.Printf("[start app handler] error starting app: %v", err)
			writeResponse(w, http.StatusInternalServerError, "error starting remote app", nil)
			return
		}
		respData["pid"] = fmt.Sprintf("%d", pid)
		writeResponse(w, http.StatusAccepted, fmt.Sprintf("Starting app: %s", appName), respData)
	}
}

func startSubprocess(srcPath string, envVars map[string]string) (int, error) {
	pidCh := make(chan int, 0)
	go func(ch chan<- int) {
		cmd := exec.Command("sh", "-c", srcPath)
		cmd.Env = os.Environ()
		if envVars != nil {
			for k, v := range envVars {
				cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
			}
		}
		if err := cmd.Start(); err != nil {
			log.Printf("error starting processes: %v", err)
			ch <- 0
			return
		}
		ppid := cmd.Process.Pid
		timeout := int64(1000) // milliseconds
		start := time.Now()
		for {
			now := time.Now()
			delta := now.Sub(start)
			list, err := ps.Processes()
			if err != nil {
				log.Printf("error getting processes: %v", err)
			}
			pid := 0
			for _, p := range list {
				if p.PPid() == ppid {
					pid = p.Pid()
					break
				}
			}
			if pid != 0 {
				log.Printf("Found child PID %d in %d ms", pid, delta.Milliseconds())
				ch <- pid
				break
			}
			if delta.Milliseconds() >= timeout {
				log.Printf("WARN: failed to find child PID in %dms", timeout)
				ch <- pid
				break
			}
			time.Sleep(1 * time.Millisecond)
		}
		cmd.CombinedOutput()
	}(pidCh)
	pid := <-pidCh
	log.Printf("Started process with pid: %d", pid)
	return pid, nil
}

func prepExecStr(execStr string) string {
	res := execStr
	// Replace file template vars with home directory.
	res = strings.ReplaceAll(execStr, "%F", os.Getenv("HOME"))

	return res
}

func tempFileName(prefix, suffix string) string {
	randBytes := make([]byte, 16)
	rand.Read(randBytes)
	return filepath.Join(os.TempDir(), prefix+hex.EncodeToString(randBytes)+suffix)
}

func writeResponse(w http.ResponseWriter, statusCode int, message string, data interface{}) {
	status := StatusResponse{
		Code:   statusCode,
		Status: message,
		Data:   data,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	enc.Encode(status)
}
