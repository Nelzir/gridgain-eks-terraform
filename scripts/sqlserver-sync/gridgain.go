package main

import (
	"context"
	"fmt"
	"strings"
	"time"

	gridgain "github.com/oscarmherrera/ggv9-go-client"
)

type GridGainClient struct {
	client gridgain.Client
}

func NewGridGainClient(host string, port int, username, password string) (*GridGainClient, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	builder := gridgain.NewClientBuilder().
		Addresses(fmt.Sprintf("%s:%d", host, port)).
		ConnectTimeout(10 * time.Second).
		OperationTimeout(30 * time.Second)

	if username != "" && password != "" {
		builder = builder.WithAuth(username, password)
	}

	client, err := builder.Build(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to GridGain: %w", err)
	}

	return &GridGainClient{client: client}, nil
}

func (c *GridGainClient) Close() error {
	if c.client != nil {
		return c.client.Close()
	}
	return nil
}

func (c *GridGainClient) Upsert(ctx context.Context, table string, columns []string, values []interface{}) error {
	placeholders := make([]string, len(columns))
	for i := range placeholders {
		placeholders[i] = "?"
	}

	// Try delete first, then insert (simple upsert for GridGain 9)
	deleteQuery := fmt.Sprintf("DELETE FROM %s WHERE %s = ?", table, columns[0])
	rs, err := c.client.SQL().Execute(ctx, nil, deleteQuery, values[0])
	if err == nil {
		rs.Close()
	}

	insertQuery := fmt.Sprintf(
		"INSERT INTO %s (%s) VALUES (%s)",
		table,
		strings.Join(columns, ", "),
		strings.Join(placeholders, ", "),
	)

	rs, err = c.client.SQL().Execute(ctx, nil, insertQuery, values...)
	if err != nil {
		return fmt.Errorf("upsert failed: %w", err)
	}
	defer rs.Close()

	return nil
}

func (c *GridGainClient) Delete(ctx context.Context, table string, id interface{}) error {
	query := fmt.Sprintf("DELETE FROM %s WHERE id = ?", table)

	rs, err := c.client.SQL().Execute(ctx, nil, query, id)
	if err != nil {
		return fmt.Errorf("delete failed: %w", err)
	}
	defer rs.Close()

	return nil
}

func (c *GridGainClient) ExecuteSQL(ctx context.Context, query string, args ...interface{}) error {
	rs, err := c.client.SQL().Execute(ctx, nil, query, args...)
	if err != nil {
		return err
	}
	defer rs.Close()
	return nil
}
