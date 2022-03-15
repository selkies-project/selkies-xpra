package remote_apps

import (
	"log"

	"github.com/fsnotify/fsnotify"
)

func StartDirWatcher(paths []string, onCreate, onMod, onRemove func(srcPath string)) (*fsnotify.Watcher, error) {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		log.Fatal(err)
	}

	go func() {
		for {
			select {
			case event, ok := <-watcher.Events:
				if !ok {
					return
				}
				if event.Op&fsnotify.Create == fsnotify.Create {
					if onCreate != nil {
						onCreate(event.Name)
					}
				}
				if event.Op&fsnotify.Write == fsnotify.Write {
					if onMod != nil {
						onMod(event.Name)
					}
				}
				if event.Op&fsnotify.Remove == fsnotify.Remove {
					if onRemove != nil {
						onRemove(event.Name)
					}
				}
			case err, ok := <-watcher.Errors:
				if !ok {
					return
				}
				log.Printf("ERROR: fsnotify error: %v", err)
			}
		}
	}()

	for _, watchDir := range paths {
		err = watcher.Add(watchDir)
		if err != nil {
			return watcher, err
		}
		log.Printf("INFO: Watching for changes in: %s", watchDir)
	}
	return watcher, nil
}
