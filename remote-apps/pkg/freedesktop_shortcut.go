package remote_apps

import (
	"bufio"
	"bytes"
	"fmt"
	"image"
	"image/png"
	"io"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"text/template"

	"golang.org/x/image/draw"
)

type FreedeskopShortcutEntryField struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

type FreedeskopShortcutEntryFields []FreedeskopShortcutEntryField

type FreedesktopShortcutDesktopEntry struct {
	IconPNGData []byte                        `json:"iconData"`
	Fields      FreedeskopShortcutEntryFields `json:"fields"`
}

type FreedeskopShortcutDesktopAction struct {
	Action      string                        `json:"action"`
	IconPNGData []byte                        `json:"iconData"`
	Fields      FreedeskopShortcutEntryFields `json:"fields"`
}

type FreedeskopShortcut struct {
	Path           string                            `json:"path"`
	DesktopEntry   FreedesktopShortcutDesktopEntry   `json:"desktopEntry"`
	DesktopActions []FreedeskopShortcutDesktopAction `json:"desktopAction"`
}

func NewFreeDesktopShortcutFromFile(srcPath string) (FreedeskopShortcut, error) {
	fds := FreedeskopShortcut{
		Path: srcPath,
	}

	parseDesktopEntryRE := regexp.MustCompile("\\[Desktop Entry\\]")
	parseDesktopActionRE := regexp.MustCompile("\\[Desktop Action (.*)\\]")
	parseEntryFieldRE := regexp.MustCompile("^(.*?)=(.*)$")

	f, err := os.Open(srcPath)
	if err != nil {
		return fds, err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	scanner.Split(bufio.ScanLines)

	desktopEntry := FreedesktopShortcutDesktopEntry{
		Fields: make(FreedeskopShortcutEntryFields, 0),
	}
	desktopActions := make([]FreedeskopShortcutDesktopAction, 0)
	lastActionSection := ""
	var currAction *FreedeskopShortcutDesktopAction
	currSection := ""
	for scanner.Scan() {
		line := scanner.Text()
		deMa := parseDesktopEntryRE.FindStringSubmatch(line)
		if len(deMa) > 0 {
			currSection = "entry"
		}
		daMa := parseDesktopActionRE.FindStringSubmatch(line)
		if len(daMa) > 0 {
			currSection = "action"
			if line != lastActionSection {
				if currAction != nil {
					// Add action to array
					desktopActions = append(desktopActions, *currAction)
				}
				currAction = &FreedeskopShortcutDesktopAction{
					Action: daMa[1],
					Fields: make(FreedeskopShortcutEntryFields, 0),
				}

			}
		}
		fieldMa := parseEntryFieldRE.FindStringSubmatch(line)
		if len(fieldMa) > 0 {
			key := fieldMa[1]
			value := fieldMa[2]
			if key == "Icon" {
				pngdata, err := ReadIconToPNG(value)
				if err != nil {
					log.Printf("%v", err)
					continue
				}
				if currSection == "entry" {
					desktopEntry.IconPNGData = pngdata
				} else if currSection == "action" {
					currAction.IconPNGData = pngdata
				}
			}
			if currSection == "entry" {
				desktopEntry.Fields = append(desktopEntry.Fields, FreedeskopShortcutEntryField{Key: key, Value: value})
			} else if currSection == "action" {
				currAction.Fields = append(currAction.Fields, FreedeskopShortcutEntryField{Key: key, Value: value})
			} else {
				log.Printf("WARN: parsing desktop shortcut, found field outside of section.")
			}
		}
	}
	if currAction != nil {
		desktopActions = append(desktopActions, *currAction)
	}
	fds.DesktopEntry = desktopEntry
	fds.DesktopActions = desktopActions

	if len(fds.DesktopEntry.Fields) == 0 {
		return fds, fmt.Errorf("file has no fields or is invalid: %s", fds.Path)
	}

	return fds, nil
}

func (s *FreedeskopShortcut) Write(f io.Writer) error {
	tpl := `[Desktop Entry]{{range $f := .DesktopEntry.Fields}}
{{$f.Key}}={{$f.Value}}{{end}}
{{range $a := .DesktopActions}}
[Desktop Action {{$a.Action}}]{{range $f := $a.Fields}}
{{$f.Key}}={{$f.Value}}{{end}}
{{end}}`
	t, err := template.New("shortcut").Parse(tpl)
	if err != nil {
		return err
	}
	return t.Execute(f, *s)
}

func ReadIconToPNG(srcIcon string) ([]byte, error) {
	data := make([]byte, 0)

	iconSizeRE := regexp.MustCompile(".*48x48.*|.*/48/.*")

	srcIconPath := ""

	fileExt := filepath.Ext(strings.ToLower(srcIcon))
	if fileExt == ".png" {
		srcIconPath = srcIcon
	} else if fileExt == "" {
		// Try to find named icon in canonical path.
		icons, err := filepath.Glob(fmt.Sprintf("/usr/share/icons/*/*/*/%s.png", srcIcon))
		if err != nil {
			return data, fmt.Errorf("error searching for icon in canonical path for: %s", srcIcon)
		}
		for _, iconPath := range icons {
			if iconSizeRE.MatchString(iconPath) {
				srcIconPath = iconPath
				break
			}
		}
	} else {
		// Look in same directory for .png file.
		pngFilePath := strings.ReplaceAll(srcIcon, fileExt, ".png")
		if _, err := os.Stat(pngFilePath); !os.IsNotExist(err) {
			srcIconPath = pngFilePath
		}
	}

	f, err := os.Open(srcIconPath)
	if err != nil {
		return data, err
	}
	defer f.Close()

	// Resize icon to be 48x48
	pngsrc, _ := png.Decode(f)
	pngdst := image.NewRGBA(image.Rect(0, 0, 48, 48))
	draw.BiLinear.Scale(pngdst, pngdst.Rect, pngsrc, pngsrc.Bounds(), draw.Over, nil)
	buf := bytes.NewBuffer(make([]byte, 0))
	png.Encode(buf, pngdst)

	data = buf.Bytes()
	return data, nil
}

func (f *FreedeskopShortcutEntryFields) Get(name string) string {
	for _, field := range *f {
		if field.Key == name {
			return field.Value
		}
	}
	return ""
}

func (f *FreedeskopShortcutEntryFields) Set(name, value string) {
	newFields := FreedeskopShortcutEntryFields{}
	found := false
	for _, field := range *f {
		newField := FreedeskopShortcutEntryField{
			Key:   field.Key,
			Value: field.Value,
		}
		if field.Key == name {
			found = true
			newField = FreedeskopShortcutEntryField{
				Key:   name,
				Value: value,
			}
		}
		newFields = append(newFields, newField)
	}
	if !found {
		newFields = append(newFields, FreedeskopShortcutEntryField{
			Key:   name,
			Value: value,
		})
	}
	*f = newFields
}
