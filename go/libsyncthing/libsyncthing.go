package libsyncthing

import (
	"context"
	"crypto/tls"
	"os"
	"path/filepath"
	"sync"

	"github.com/syncthing/syncthing/lib/config"
	"github.com/syncthing/syncthing/lib/db/backend"
	"github.com/syncthing/syncthing/lib/events"
	"github.com/syncthing/syncthing/lib/fs"
	"github.com/syncthing/syncthing/lib/protocol"
	"github.com/syncthing/syncthing/lib/svcutil"
	"github.com/syncthing/syncthing/lib/syncthing"
	"github.com/syncthing/syncthing/lib/tlsutil"
)

var (
	app     *syncthing.App
	cfg     config.Wrapper
	mu      sync.Mutex
	myID    protocol.DeviceID
	dataDir string
	running bool
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

	evLogger := events.NewLogger()
	go evLogger.Serve(context.Background())

	cfgPath := filepath.Join(dataDir, "config.xml")
	cfg, _, err = config.Load(cfgPath, myID, evLogger)
	if err != nil {
		cfg, err = defaultConfig(cfgPath, myID, evLogger)
		if err != nil {
			mu.Unlock()
			return err
		}
	}

	dbPath := filepath.Join(dataDir, "index-v0.14.0.db")
	ldb, err := backend.OpenLevelDB(dbPath, backend.TuningAuto)
	if err != nil {
		mu.Unlock()
		return err
	}

	opts := syncthing.Options{
		NoUpgrade:  true,
		Verbose:    false,
	}

	app, err = syncthing.New(cfg, ldb, evLogger, cert, opts)
	if err != nil {
		mu.Unlock()
		return err
	}

	// Set running before releasing mutex so GetDeviceID works
	running = true
	mu.Unlock()

	// Start app without holding mutex - this may block on network
	if err := app.Start(); err != nil {
		mu.Lock()
		running = false
		app = nil
		mu.Unlock()
		return err
	}

	return nil
}

func defaultConfig(cfgPath string, myID protocol.DeviceID, evLogger events.Logger) (config.Wrapper, error) {
	newCfg := config.New(myID)
	newCfg.GUI.Enabled = false
	return config.Wrap(cfgPath, newCfg, myID, evLogger), nil
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

	waiter, err := cfg.Modify(func(c *config.Configuration) {
		for i := range c.Folders {
			if c.Folders[i].ID == folderID {
				c.Folders[i].Path = folderPath
				return
			}
		}
		c.Folders = append(c.Folders, config.FolderConfiguration{
			ID:              folderID,
			Path:            folderPath,
			Type:            config.FolderTypeSendReceive,
			FilesystemType:  fs.FilesystemTypeBasic,
			RescanIntervalS: 60,
			FSWatcherEnabled: true,
		})
	})
	if err != nil {
		return err
	}
	waiter.Wait()
	return nil
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

	waiter, err := cfg.Modify(func(c *config.Configuration) {
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
	if err != nil {
		return err
	}
	waiter.Wait()
	return nil
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

	waiter, err := cfg.Modify(func(c *config.Configuration) {
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
	if err != nil {
		return err
	}
	waiter.Wait()
	return nil
}

func Rescan(folderID string) error {
	return nil
}
