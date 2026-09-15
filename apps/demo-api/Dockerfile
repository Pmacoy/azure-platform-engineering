# Por que Go aqui, sendo que o resto do projeto não é Go: porque o tamanho da
# imagem é uma decisão de plataforma, não de gosto. Um binário estático cabe
# numa imagem sem sistema operacional, e isso muda três coisas concretas --
# o tempo de pull em cada nó novo que entra no cluster, a superfície de ataque
# (não existe shell nem gerenciador de pacotes para um invasor usar), e o
# volume de CVEs que o scanner vai reportar todo mês em pacotes que a
# aplicação nunca chamou.

# ── Estágio 1: build ────────────────────────────────────────────────────────
FROM golang:1.23-alpine AS build

WORKDIR /src

# Copiar o go.mod antes do código não é frescura de organização: o Docker faz
# cache por camada, então enquanto as dependências não mudarem, esta camada é
# reaproveitada e o download não se repete a cada build.
COPY go.mod ./
RUN go mod download

COPY main.go ./

# VERSION chega do pipeline (o SHA do commit) e é gravado dentro do binário.
ARG VERSION=dev

# CGO_ENABLED=0 produz um binário estático, sem dependência de libc -- é o que
# permite rodar numa imagem que não tem sistema operacional nenhum.
# -s -w removem tabela de símbolos e informação de debug: imagem menor.
RUN CGO_ENABLED=0 GOOS=linux go build \
      -ldflags="-s -w -X main.version=${VERSION}" \
      -o /out/demo-api .

# ── Estágio 2: runtime ──────────────────────────────────────────────────────
# distroless/static contém o binário, certificados de CA e nada mais. Sem
# shell, sem apk, sem coreutils. A tag :nonroot já vem com um usuário sem
# privilégio configurado.
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/demo-api /demo-api

# NUMÉRICO, não `nonroot:nonroot`. O Kubernetes, quando o manifesto pede
# `runAsNonRoot: true`, precisa provar que o usuário não é root ANTES de
# iniciar o container -- e resolver um nome exigiria ler o /etc/passwd de
# dentro da imagem, que numa distroless não serve para isso. Com o UID
# explícito, a imagem se descreve sozinha e funciona sob qualquer política
# de segurança que exija usuário não-root.
#
# 65532 é o UID do usuário `nonroot` das imagens distroless.
USER 65532:65532

EXPOSE 8080

ENTRYPOINT ["/demo-api"]
