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

func NewGridGainClient(host string, port int) (*GridGainClient, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	client, err := gridgain.NewClientBuilder().
		Addresses(fmt.Sprintf("%s:%d", host, port)).
		ConnectTimeout(10 * time.Second).
		OperationTimeout(30 * time.Second).
		Build(ctx)
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

	query := fmt.Sprintf(
		"MERGE INTO %s (%s) KEY(%s) VALUES (%s)",
		table,
		strings.Join(columns, ", "),
		columns[0], // assumes first column is PK
		strings.Join(placeholders, ", "),
	)

	rs, err := c.client.SQL().Execute(ctx, nil, query, values...)
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
