package main

import (
	"fmt"
	"net/http"
	"os"
)

func handler(w http.ResponseWriter, r *http.Request) {
	hostname, err := os.Hostname()
	if err != nil {
		panic(err)
	}
	fmt.Fprintln(w, "[Hostname]")
	fmt.Fprintln(w, hostname)

	fmt.Fprintln(w)
	fmt.Fprintln(w, "[Messages]")
	fmt.Fprintln(w, "Hello World!")

}

func main() {
	http.HandleFunc("/", handler)
	http.ListenAndServe(":80", nil)
}
