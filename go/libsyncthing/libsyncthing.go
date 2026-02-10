package libsyncthing

import (
	"context"
	"crypto/tls"
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
	"sync"
	"time"

	"github.com/syncthing/syncthing/lib/config"
	"github.com/syncthing/syncthing/lib/db/backend"
	"github.com/syncthing/syncthing/lib/events"
	"github.com/syncthing/syncthing/lib/fs"
	"github.com/syncthing/syncthing/lib/locations"
	"github.com/syncthing/syncthing/lib/protocol"
	"github.com/syncthing/syncthing/lib/svcutil"
	"github.com/syncthing/syncthing/lib/syncthing"
	"github.com/syncthing/syncthing/lib/tlsutil"
)

var (
	app       *syncthing.App
	cfg       config.Wrapper
	evLogger  events.Logger
	mu        sync.Mutex
	myID      protocol.DeviceID
	dataDir   string
	running   bool
	eventLog  []string
	eventMu   sync.Mutex
)

func Start(dir string) error {
	mu.Lock()

	if running {
		mu.Unlock()
		return nil
	}

	dataDir = dir
	if err := os.MkdirAll(dataDir, 0700); err != nil {
		mu.Unlock()
		return err
	}

	// Initialize locations package so Syncthing internals use our data directory
	if err := locations.SetBaseDir(locations.ConfigBaseDir, dataDir); err != nil {
		mu.Unlock()
		return err
	}
	if err := locations.SetBaseDir(locations.DataBaseDir, dataDir); err != nil {
		mu.Unlock()
		return err
	}

	certFile := filepath.Join(dataDir, "cert.pem")
	keyFile := filepath.Join(dataDir, "key.pem")

	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		cert, err = tlsutil.NewCertificate(certFile, keyFile, "syncthing", 365*20)
		if err != nil {
			mu.Unlock()
			return err
		}
	}

	myID = protocol.NewDeviceID(cert.Certificate[0])

	evLogger = events.NewLogger()
	go evLogger.Serve(context.Background())

	cfgPath := filepath.Join(dataDir, "config.xml")

	// Always start fresh - delete old config that may have bad networking settings
	os.Remove(cfgPath)
	cfg, err = defaultConfig(cfgPath, myID, evLogger)
	if err != nil {
		mu.Unlock()
		return err
	}

	// Start config service - Syncthing's cfg.Modify() sends to a queue
	// that cfg.Serve() processes. Without this, any Modify() call deadlocks.
	go cfg.Serve(context.Background())

	dbPath := filepath.Join(dataDir, "index-v0.14.0.db")
	ldb, err := backend.OpenLevelDB(dbPath, backend.TuningAuto)
	if err != nil {
		mu.Unlock()
		return err
	}

	app, err = syncthing.New(cfg, ldb, evLogger, cert, syncthing.Options{
		NoUpgrade: true,
	})
	if err != nil {
		mu.Unlock()
		return err
	}

	running = true
	mu.Unlock()

	go func() {
		defer func() {
			if r := recover(); r != nil {
				addEvent(fmt.Sprintf("PANIC: %v\n%s", r, debug.Stack()))
				mu.Lock()
				running = false
				app = nil
				mu.Unlock()
			}
		}()

		err := app.Start()
		if err != nil {
			addEvent(fmt.Sprintf("Start error: %v", err))
			mu.Lock()
			running = false
			app = nil
			mu.Unlock()
			return
		}
		addEvent("Sync engine started")
		go listenEvents()
	}()

	return nil
}

func defaultConfig(cfgPath string, myID protocol.DeviceID, evLogger events.Logger) (config.Wrapper, error) {
	newCfg := config.New(myID)
	newCfg.GUI.Enabled = false

	// Enable local discovery so phone and desktop find each other on same WiFi
	newCfg.Options.LocalAnnEnabled = true
	// Listen on a dynamic TCP port for incoming connections
	newCfg.Options.RawListenAddresses = []string{"tcp://0.0.0.0:0"}

	// Keep these disabled for iOS simplicity
	newCfg.Options.GlobalAnnEnabled = false
	newCfg.Options.RelaysEnabled = false
	newCfg.Options.NATEnabled = false
	newCfg.Options.CREnabled = false

	wrapper := config.Wrap(cfgPath, newCfg, myID, evLogger)
	if err := wrapper.Save(); err != nil {
		return nil, err
	}
	return wrapper, nil
}

func Stop() {
	mu.Lock()
	defer mu.Unlock()

	if app != nil {
		app.Stop(svcutil.ExitSuccess)
		app.Wait()
		app = nil
	}
	running = false
}

func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return running
}

func GetDeviceID() string {
	mu.Lock()
	defer mu.Unlock()
	return myID.String()
}

func SetFolder(folderID, folderPath string) error {
	mu.Lock()
	defer mu.Unlock()

	if cfg == nil {
		return nil
	}

	_, err := cfg.Modify(func(c *config.Configuration) {
		for i := range c.Folders {
			if c.Folders[i].ID == folderID {
				c.Folders[i].Path = folderPath
				return
			}
		}
		c.Folders = append(c.Folders, config.FolderConfiguration{
			ID:               folderID,
			Path:             folderPath,
			Type:             config.FolderTypeSendReceive,
			FilesystemType:   fs.FilesystemTypeBasic,
			RescanIntervalS:  60,
			FSWatcherEnabled: true,
		})
	})
	return err
}

func AddDevice(deviceID, name string) error {
	mu.Lock()
	defer mu.Unlock()

	if cfg == nil {
		return nil
	}

	id, err := protocol.DeviceIDFromString(deviceID)
	if err != nil {
		return err
	}

	_, err = cfg.Modify(func(c *config.Configuration) {
		for _, d := range c.Devices {
			if d.DeviceID == id {
				return
			}
		}
		c.Devices = append(c.Devices, config.DeviceConfiguration{
			DeviceID: id,
			Name:     name,
		})
	})
	return err
}

func ShareFolderWithDevice(folderID, deviceID string) error {
	mu.Lock()
	defer mu.Unlock()

	if cfg == nil {
		return nil
	}

	id, err := protocol.DeviceIDFromString(deviceID)
	if err != nil {
		return err
	}

	_, err = cfg.Modify(func(c *config.Configuration) {
		for i := range c.Folders {
			if c.Folders[i].ID != folderID {
				continue
			}
			for _, d := range c.Folders[i].Devices {
				if d.DeviceID == id {
					return
				}
			}
			c.Folders[i].Devices = append(c.Folders[i].Devices, config.FolderDeviceConfiguration{
				DeviceID: id,
			})
			return
		}
	})
	return err
}

func Rescan(folderID string) error {
	return nil
}

func listenEvents() {
	if evLogger == nil {
		return
	}

	sub := evLogger.Subscribe(events.AllEvents)
	defer sub.Unsubscribe()

	for {
		ev, err := sub.Poll(time.Minute)
		if err != nil {
			continue // timeout — no events, just re-poll
		}

		var msg string
		switch ev.Type {
		case events.DeviceConnected:
			msg = "Device connected"
		case events.DeviceDisconnected:
			msg = "Device disconnected"
		case events.StateChanged:
			if data, ok := ev.Data.(map[string]interface{}); ok {
				msg = fmt.Sprintf("Folder %v: %v -> %v", data["folder"], data["from"], data["to"])
			}
		case events.FolderCompletion:
			if data, ok := ev.Data.(map[string]interface{}); ok {
				msg = fmt.Sprintf("Folder %v: %.1f%% complete", data["folder"], data["completion"])
			}
		case events.ItemFinished:
			if data, ok := ev.Data.(map[string]interface{}); ok {
				msg = fmt.Sprintf("File %v: %v", data["item"], data["action"])
			}
		case events.FolderErrors:
			msg = "Folder errors occurred"
		}

		if msg != "" {
			addEvent(msg)
		}
	}
}

func addEvent(msg string) {
	eventMu.Lock()
	defer eventMu.Unlock()

	timestamp := time.Now().Format("15:04:05")
	entry := fmt.Sprintf("[%s] %s", timestamp, msg)
	eventLog = append(eventLog, entry)
	if len(eventLog) > 50 {
		eventLog = eventLog[1:]
	}
}

func GetEvents() string {
	eventMu.Lock()
	defer eventMu.Unlock()

	if len(eventLog) == 0 {
		return ""
	}

	result := ""
	for _, e := range eventLog {
		result += e + "\n"
	}
	eventLog = nil
	return result
}
