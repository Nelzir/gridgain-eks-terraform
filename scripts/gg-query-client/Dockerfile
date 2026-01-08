FROM golang:1.24-alpine AS builder

WORKDIR /app

# Copy GridGain client (from parent context)
COPY ggv9-go-client/ /ggv9-go-client/

# Copy module files
COPY gridgain-eks-terraform/scripts/gg-query-client/go.mod ./

# Allow newer toolchain requirements
ENV GOTOOLCHAIN=auto

# Copy source
COPY gridgain-eks-terraform/scripts/gg-query-client/*.go ./

# Generate go.sum and download dependencies
RUN go mod tidy && go mod download

# Build
RUN CGO_ENABLED=0 GOOS=linux go build -o gg-query-client .

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=builder /app/gg-query-client .
EXPOSE 8080
ENTRYPOINT ["./gg-query-client"]
