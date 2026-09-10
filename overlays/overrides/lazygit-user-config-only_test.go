package config

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

func TestDotfilesConfigTrust(t *testing.T) {
	for _, explicit := range []bool{false, true} {
		name := "user config"
		if explicit {
			name = "explicit config"
		}
		t.Run(name, func(t *testing.T) {
			root := t.TempDir()
			write := func(path, content string) {
				t.Helper()
				if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
					t.Fatal(err)
				}
			}
			t.Setenv("CONFIG_DIR", filepath.Join(root, "user"))
			t.Setenv("LG_CONFIG_FILE", "")
			global := filepath.Join(root, "user", "config.yml")
			if explicit {
				global = filepath.Join(root, "explicit.yml")
				t.Setenv("LG_CONFIG_FILE", global)
			}
			write(global, "gui:\n  scrollHeight: 7\n")
			c, err := NewAppConfig("lazygit", "test", "", "", "test", false, root)
			if err != nil {
				t.Fatal(err)
			}
			for _, path := range []string{
				filepath.Join(root, ".lazygit.yml"),
				filepath.Join(root, "repo", ".lazygit.yml"),
				filepath.Join(root, "repo", ".git", "lazygit.yml"),
			} {
				write(path, "gui:\n  scrollHeight: 99\n")
				if err := c.ReloadUserConfigForRepo([]*ConfigFile{{Path: path, Policy: ConfigFilePolicySkipIfMissing}}); err != nil {
					t.Fatal(err)
				}
				if c.GetUserConfig().Gui.ScrollHeight != 7 || !reflect.DeepEqual(c.GetUserConfigPaths(), []string{global}) {
					t.Fatalf("repository config loaded: %v", c.GetUserConfigPaths())
				}
				// A repository edit must not enter the hot-reload path, either.
				write(path, "gui: [invalid")
				if err, changed := c.ReloadChangedUserConfigFiles(); err != nil || changed {
					t.Fatalf("repository config reloaded: changed=%v, err=%v", changed, err)
				}
			}
			write(global, "gui:\n  scrollHeight: 8\n")
			later := time.Now().Add(time.Hour)
			if err := os.Chtimes(global, later, later); err != nil {
				t.Fatal(err)
			}
			if err, changed := c.ReloadChangedUserConfigFiles(); err != nil || !changed || c.GetUserConfig().Gui.ScrollHeight != 8 {
				t.Fatalf("user config did not reload: changed=%v, err=%v", changed, err)
			}
		})
	}
}
