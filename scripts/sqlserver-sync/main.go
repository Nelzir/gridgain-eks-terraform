package main

import (
	"context"
	"database/sql"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	_ "github.com/denisenkom/go-mssqldb"
)

type Config struct {
	SQLServerConn    string
	GridGainHost     string
	GridGainPort     int
	GridGainUser     string
	GridGainPassword string
	Tables           []string
	PollInterval     time.Duration
	StateFile        string
}

type SyncState struct {
	LastVersion int64 `json:"last_version"`
}

func main() {
	cfg := parseFlags()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		log.Println("Shutting down...")
		cancel()
	}()

	if err := run(ctx, cfg); err != nil {
		log.Fatalf("Error: %v", err)
	}
}

func parseFlags() Config {
	cfg := Config{}

	flag.StringVar(&cfg.SQLServerConn, "sqlserver", "", "SQL Server connection string")
	flag.StringVar(&cfg.GridGainHost, "gg-host", "localhost", "GridGain host")
	flag.IntVar(&cfg.GridGainPort, "gg-port", 10800, "GridGain client port")
	flag.StringVar(&cfg.GridGainUser, "gg-user", "", "GridGain username (optional)")
	flag.StringVar(&cfg.GridGainPassword, "gg-password", "", "GridGain password (optional)")
	flag.DurationVar(&cfg.PollInterval, "interval", 30*time.Second, "Poll interval")
	flag.StringVar(&cfg.StateFile, "state-file", "sync_state.json", "State file path")

	var tables string
	flag.StringVar(&tables, "tables", "", "Comma-separated list of tables to sync")

	flag.Parse()

	if cfg.SQLServerConn == "" {
		cfg.SQLServerConn = os.Getenv("SQLSERVER_CONN")
	}
	if cfg.GridGainUser == "" {
		cfg.GridGainUser = os.Getenv("GRIDGAIN_USER")
	}
	if cfg.GridGainPassword == "" {
		cfg.GridGainPassword = os.Getenv("GRIDGAIN_PASSWORD")
	}
	if tables == "" {
		tables = os.Getenv("SYNC_TABLES")
	}
	if tables != "" {
		cfg.Tables = strings.Split(tables, ",")
	}

	if cfg.SQLServerConn == "" {
		log.Fatal("SQL Server connection string required (-sqlserver or SQLSERVER_CONN)")
	}
	if len(cfg.Tables) == 0 {
		log.Fatal("At least one table required (-tables or SYNC_TABLES)")
	}

	return cfg
}

func run(ctx context.Context, cfg Config) error {
	sqlDB, err := sql.Open("sqlserver", cfg.SQLServerConn)
	if err != nil {
		return fmt.Errorf("failed to connect to SQL Server: %w", err)
	}
	defer sqlDB.Close()

	if err := sqlDB.PingContext(ctx); err != nil {
		return fmt.Errorf("failed to ping SQL Server: %w", err)
	}
	log.Println("Connected to SQL Server")

	ggClient, err := NewGridGainClient(cfg.GridGainHost, cfg.GridGainPort, cfg.GridGainUser, cfg.GridGainPassword)
	if err != nil {
		return fmt.Errorf("failed to connect to GridGain: %w", err)
	}
	defer ggClient.Close()
	log.Println("Connected to GridGain")

	state := loadState(cfg.StateFile)

	ticker := time.NewTicker(cfg.PollInterval)
	defer ticker.Stop()

	// Initial sync
	if err := syncChanges(ctx, sqlDB, ggClient, cfg.Tables, &state); err != nil {
		log.Printf("Sync error: %v", err)
	}
	saveState(cfg.StateFile, state)

	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			if err := syncChanges(ctx, sqlDB, ggClient, cfg.Tables, &state); err != nil {
				log.Printf("Sync error: %v", err)
				continue
			}
			saveState(cfg.StateFile, state)
		}
	}
}

func syncChanges(ctx context.Context, sqlDB *sql.DB, ggClient *GridGainClient, tables []string, state *SyncState) error {
	currentVersion, err := getCurrentVersion(ctx, sqlDB)
	if err != nil {
		return fmt.Errorf("failed to get current version: %w", err)
	}

	if state.LastVersion == 0 {
		log.Println("Initial load - syncing all data")
		for _, table := range tables {
			if err := initialLoad(ctx, sqlDB, ggClient, table); err != nil {
				return fmt.Errorf("initial load of %s failed: %w", table, err)
			}
		}
		state.LastVersion = currentVersion
		return nil
	}

	if currentVersion == state.LastVersion {
		log.Println("No changes detected")
		return nil
	}

	for _, table := range tables {
		if err := syncTableChanges(ctx, sqlDB, ggClient, table, state.LastVersion); err != nil {
			return fmt.Errorf("sync of %s failed: %w", table, err)
		}
	}

	state.LastVersion = currentVersion
	log.Printf("Synced to version %d", currentVersion)
	return nil
}

func getCurrentVersion(ctx context.Context, db *sql.DB) (int64, error) {
	var version int64
	err := db.QueryRowContext(ctx, "SELECT CHANGE_TRACKING_CURRENT_VERSION()").Scan(&version)
	return version, err
}

func initialLoad(ctx context.Context, sqlDB *sql.DB, ggClient *GridGainClient, table string) error {
	log.Printf("Loading all rows from %s", table)

	rows, err := sqlDB.QueryContext(ctx, fmt.Sprintf("SELECT * FROM %s", table))
	if err != nil {
		return err
	}
	defer rows.Close()

	columns, err := rows.Columns()
	if err != nil {
		return err
	}

	count := 0
	for rows.Next() {
		values := make([]interface{}, len(columns))
		valuePtrs := make([]interface{}, len(columns))
		for i := range values {
			valuePtrs[i] = &values[i]
		}

		if err := rows.Scan(valuePtrs...); err != nil {
			return err
		}

		// Convert types for GridGain compatibility
		convertedValues := convertValues(values)

		if err := ggClient.Upsert(ctx, table, columns, convertedValues); err != nil {
			return err
		}
		count++
	}

	log.Printf("Loaded %d rows from %s", count, table)
	return rows.Err()
}

func syncTableChanges(ctx context.Context, sqlDB *sql.DB, ggClient *GridGainClient, table string, lastVersion int64) error {
	query := fmt.Sprintf(`
		SELECT CT.SYS_CHANGE_OPERATION, CT.Id
		FROM CHANGETABLE(CHANGES %s, %d) AS CT
	`, table, lastVersion)

	rows, err := sqlDB.QueryContext(ctx, query)
	if err != nil {
		return err
	}
	defer rows.Close()

	inserts, updates, deletes := 0, 0, 0

	for rows.Next() {
		var op string
		var id interface{}
		if err := rows.Scan(&op, &id); err != nil {
			return err
		}

		switch op {
		case "I", "U":
			if err := upsertRow(ctx, sqlDB, ggClient, table, id); err != nil {
				return err
			}
			if op == "I" {
				inserts++
			} else {
				updates++
			}
		case "D":
			if err := ggClient.Delete(ctx, table, id); err != nil {
				return err
			}
			deletes++
		}
	}

	if inserts+updates+deletes > 0 {
		log.Printf("%s: %d inserts, %d updates, %d deletes", table, inserts, updates, deletes)
	}

	return rows.Err()
}

func upsertRow(ctx context.Context, sqlDB *sql.DB, ggClient *GridGainClient, table string, id interface{}) error {
	query := fmt.Sprintf("SELECT * FROM %s WHERE Id = @p1", table)
	rows, err := sqlDB.QueryContext(ctx, query, id)
	if err != nil {
		return err
	}
	defer rows.Close()

	if !rows.Next() {
		return nil
	}

	cols, err := rows.Columns()
	if err != nil {
		return err
	}

	vals := make([]interface{}, len(cols))
	ptrs := make([]interface{}, len(cols))
	for i := range vals {
		ptrs[i] = &vals[i]
	}

	if err := rows.Scan(ptrs...); err != nil {
		return err
	}

	return ggClient.Upsert(ctx, table, cols, convertValues(vals))
}

func loadState(path string) SyncState {
	data, err := os.ReadFile(path)
	if err != nil {
		return SyncState{}
	}
	var state SyncState
	fmt.Sscanf(string(data), "%d", &state.LastVersion)
	return state
}

func saveState(path string, state SyncState) {
	os.WriteFile(path, []byte(fmt.Sprintf("%d", state.LastVersion)), 0644)
}

// convertValues handles type conversions for GridGain compatibility
func convertValues(values []interface{}) []interface{} {
	result := make([]interface{}, len(values))
	for i, v := range values {
		switch val := v.(type) {
		case []byte:
			// Try to parse as number first (for DECIMAL, MONEY, etc.)
			str := string(val)
			if f, err := strconv.ParseFloat(str, 64); err == nil {
				result[i] = f
			} else {
				result[i] = str
			}
		default:
			result[i] = v
		}
	}
	return result
}
