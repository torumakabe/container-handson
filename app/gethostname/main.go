package main

import (
	"fmt"
	"net/http"
	"os"
)

func getHostName(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "This is served by host: %s", os.Getenv("HOSTNAME"))
}
func main() {
	http.HandleFunc("/", getHostName)
	http.ListenAndServe(":8080", nil)
}
