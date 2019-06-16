# build stage
ARG GO_VERSION=1.12.6
FROM golang:${GO_VERSION}-alpine AS build-stage
RUN apk add --no-cache ca-certificates git
WORKDIR /src
COPY ./go.mod ./
RUN go mod download
COPY . .
RUN go build -o /app main.go

# production stage
FROM alpine:3.9
RUN apk add --no-cache ca-certificates
COPY --from=build-stage /app /
EXPOSE 8080
CMD ["/app"]