package main

import (
	"fmt"
	"log"
	"net/http"
	os "os"

	ocagent "contrib.go.opencensus.io/exporter/ocagent"
	"go.opencensus.io/plugin/ochttp"
	"go.opencensus.io/plugin/ochttp/propagation/tracecontext"
	"go.opencensus.io/trace"
)

func getTargetServiceURI() string {
	targetService := os.Getenv("TARGET_SERVICE")
	targetServiceURI := ""

	if len(targetService) != 0 {
		targetServiceURI = fmt.Sprintf("http://%v", targetService)
	}

	return targetServiceURI
}

func main() {
	// Register trace exporters to export the collected data.
	serviceName := os.Getenv("SERVICE_NAME")
	if len(serviceName) == 0 {
		serviceName = "go-app"
	}
	agentEndpoint := os.Getenv("OCAGENT_TRACE_EXPORTER_ENDPOINT")
	if len(agentEndpoint) == 0 {
		agentEndpoint = fmt.Sprintf("%s:%d", ocagent.DefaultAgentHost, ocagent.DefaultAgentPort)
	}

	exporter, err := ocagent.NewExporter(ocagent.WithInsecure(), ocagent.WithServiceName(serviceName), ocagent.WithAddress(agentEndpoint))
	if err != nil {
		log.Fatalf("Failed to create the agent exporter: %v", err)
	}

	trace.RegisterExporter(exporter)
	trace.ApplyConfig(trace.Config{DefaultSampler: trace.AlwaysSample()})

	client := &http.Client{Transport: &ochttp.Transport{Propagation: &tracecontext.HTTPFormat{}}}

	http.HandleFunc("/", func(w http.ResponseWriter, req *http.Request) {
		fmt.Fprintf(w, "hello world from %s", serviceName)

		targetServiceURI := getTargetServiceURI()
		if len(targetServiceURI) != 0 {
			httpFormat := &tracecontext.HTTPFormat{}
			sc, ok := httpFormat.SpanContextFromRequest(req)
			if ok {
				_, span := trace.StartSpanWithRemoteParent(req.Context(), serviceName, sc)
				defer span.End()
			}

			r, _ := http.NewRequest("GET", targetServiceURI, nil)

			// Propagate the trace header info in the outgoing requests.
			r = r.WithContext(req.Context())
			resp, err := client.Do(r)
			if err != nil {
				log.Println(err)
			} else {
				// TODO: handle response
				resp.Body.Close()
			}
		}

	})

	http.HandleFunc("/healthz", func(w http.ResponseWriter, req *http.Request) {
		w.Write([]byte("ok"))
	})

	http.HandleFunc("/readiness", func(w http.ResponseWriter, req *http.Request) {
		targetServiceURI := getTargetServiceURI()
		if len(targetServiceURI) != 0 {
			_, err := http.NewRequest("GET", targetServiceURI, nil)
			if err != nil {
				http.Error(w, "A dependent service is not ready", http.StatusServiceUnavailable)
			} else {
				w.Write([]byte("ok"))
			}
		} else {
			w.Write([]byte("ok"))
		}
	})

	log.Println("We will listen :50030")
	log.Fatal(http.ListenAndServe(":50030", &ochttp.Handler{Propagation: &tracecontext.HTTPFormat{}}))
}
