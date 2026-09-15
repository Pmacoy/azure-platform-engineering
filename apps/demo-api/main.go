// Uma API deliberadamente mínima. Ela não é o ponto do projeto -- o ponto é
// o caminho que ela percorre: commit -> build -> ACR -> Git -> Argo CD ->
// cluster. Quanto menos a aplicação fizer, mais claro fica que o que está
// sendo demonstrado é a plataforma, não o código dela.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

// Injetado em tempo de build via -ldflags (veja o Dockerfile). É assim que a
// imagem sabe dizer de qual commit ela nasceu -- sem isso, "qual versão está
// rodando em produção?" vira arqueologia.
var version = "dev"

type response struct {
	Service  string    `json:"service"`
	Version  string    `json:"version"`
	Hostname string    `json:"hostname"`
	Time     time.Time `json:"time"`
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	hostname, _ := os.Hostname()

	mux := http.NewServeMux()

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(response{
			Service:  "demo-api",
			Version:  version,
			Hostname: hostname,
			Time:     time.Now().UTC(),
		})
	})

	// Separar liveness de readiness importa: liveness responde "o processo
	// está vivo?" (se falhar, o kubelet reinicia o pod), readiness responde
	// "posso receber tráfego?" (se falhar, o Service tira o pod do
	// balanceamento sem matá-lo). Numa aplicação real, readiness checaria
	// banco e dependências; aqui as duas são triviais de propósito.
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	mux.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ready"))
	})

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("demo-api version=%s listening on :%s", version, port)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}
