package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	gridgain "github.com/oscarmherrera/ggv9-go-client"
)

type Config struct {
	ListenAddr       string
	GridGainHost     string
	GridGainPort     int
	GridGainUser     string
	GridGainPassword string
}

type QueryRequest struct {
	SQL  string        `json:"sql"`
	Args []interface{} `json:"args,omitempty"`
}

type QueryResponse struct {
	Columns []string        `json:"columns,omitempty"`
	Rows    [][]interface{} `json:"rows,omitempty"`
	Error   string          `json:"error,omitempty"`
	Latency string          `json:"latency"`
}

var ggClient gridgain.Client

func main() {
	cfg := parseFlags()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var err error
	ggClient, err = connectGridGain(ctx, cfg)
	if err != nil {
		log.Fatalf("Failed to connect to GridGain: %v", err)
	}
	defer ggClient.Close()
	log.Printf("Connected to GridGain at %s:%d", cfg.GridGainHost, cfg.GridGainPort)

	mux := http.NewServeMux()
	mux.HandleFunc("/query", handleQuery)
	mux.HandleFunc("/health", handleHealth)

	server := &http.Server{
		Addr:         cfg.ListenAddr,
		Handler:      mux,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
	}

	go func() {
		log.Printf("Starting HTTP server on %s", cfg.ListenAddr)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("HTTP server error: %v", err)
		}
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh

	log.Println("Shutting down...")
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	server.Shutdown(shutdownCtx)
}

func parseFlags() Config {
	cfg := Config{}

	flag.StringVar(&cfg.ListenAddr, "listen", ":8080", "HTTP listen address")
	flag.StringVar(&cfg.GridGainHost, "gg-host", "localhost", "GridGain host")
	flag.IntVar(&cfg.GridGainPort, "gg-port", 10800, "GridGain client port")
	flag.StringVar(&cfg.GridGainUser, "gg-user", "", "GridGain username")
	flag.StringVar(&cfg.GridGainPassword, "gg-password", "", "GridGain password")
	flag.Parse()

	if cfg.GridGainUser == "" {
		cfg.GridGainUser = os.Getenv("GG_USER")
	}
	if cfg.GridGainPassword == "" {
		cfg.GridGainPassword = os.Getenv("GG_PASS")
	}

	return cfg
}

func connectGridGain(ctx context.Context, cfg Config) (gridgain.Client, error) {
	// Resolve all IPs from headless service DNS
	addresses := resolveAddresses(cfg.GridGainHost, cfg.GridGainPort)
	log.Printf("Resolved GridGain addresses: %v", addresses)

	builder := gridgain.NewClientBuilder().
		Addresses(addresses...).
		ConnectTimeout(10 * time.Second).
		OperationTimeout(30 * time.Second).
		HeartbeatInterval(5 * time.Second).
		HealthCheckPeriod(5 * time.Second).
		ReconnectInterval(1 * time.Second)

	if cfg.GridGainUser != "" && cfg.GridGainPassword != "" {
		builder = builder.WithAuth(cfg.GridGainUser, cfg.GridGainPassword)
	}

	return builder.Build(ctx)
}

func resolveAddresses(host string, port int) []string {
	ips, err := net.LookupIP(host)
	if err != nil {
		log.Printf("DNS lookup failed for %s: %v, using as-is", host, err)
		return []string{fmt.Sprintf("%s:%d", host, port)}
	}

	addresses := make([]string, 0, len(ips))
	for _, ip := range ips {
		if ip.To4() != nil { // IPv4 only
			addresses = append(addresses, fmt.Sprintf("%s:%d", ip.String(), port))
		}
	}

	if len(addresses) == 0 {
		return []string{fmt.Sprintf("%s:%d", host, port)}
	}
	return addresses
}

func handleQuery(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req QueryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, QueryResponse{Error: "Invalid JSON: " + err.Error()})
		return
	}

	if req.SQL == "" {
		writeJSON(w, http.StatusBadRequest, QueryResponse{Error: "SQL query required"})
		return
	}

	start := time.Now()
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()

	rs, err := ggClient.SQL().Execute(ctx, nil, req.SQL, req.Args...)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, QueryResponse{
			Error:   err.Error(),
			Latency: time.Since(start).String(),
		})
		return
	}
	defer rs.Close()

	columns := rs.Columns()
	colNames := make([]string, len(columns))
	for i, col := range columns {
		colNames[i] = col.Name
	}

	var rows [][]interface{}
	for {
		page := rs.CurrentPage()
		for _, row := range page {
			rows = append(rows, row.Values())
		}
		if !rs.HasMorePages() {
			break
		}
		if err := rs.FetchNextPage(ctx); err != nil {
			writeJSON(w, http.StatusInternalServerError, QueryResponse{
				Error:   "Fetch error: " + err.Error(),
				Latency: time.Since(start).String(),
			})
			return
		}
	}

	writeJSON(w, http.StatusOK, QueryResponse{
		Columns: colNames,
		Rows:    rows,
		Latency: time.Since(start).String(),
	})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
