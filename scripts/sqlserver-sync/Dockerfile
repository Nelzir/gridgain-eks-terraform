FROM golang:1.24-alpine AS builder

WORKDIR /app

# Copy GridGain client (from parent context)
COPY ggv9-go-client/ /ggv9-go-client/

# Copy module files
COPY gridgain-eks-terraform/scripts/sqlserver-sync/go.mod ./

# Allow newer toolchain requirements
ENV GOTOOLCHAIN=auto

# Copy source first (needed for go mod tidy)
COPY gridgain-eks-terraform/scripts/sqlserver-sync/*.go ./

# Generate go.sum and download dependencies
RUN go mod tidy && go mod download

# Build
RUN CGO_ENABLED=0 GOOS=linux go build -o sqlserver-sync .

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=builder /app/sqlserver-sync .
ENTRYPOINT ["./sqlserver-sync"]
