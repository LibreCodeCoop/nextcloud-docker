# Nextcloud com SSL e Docker
- [Nextcloud com SSL e Docker](#nextcloud-com-ssl-e-docker)
  - [Configuração do Docker](#configuração-do-docker)
  - [Configuração de proxy](#configuração-de-proxy)
  - [Antes da primeira execução](#antes-da-primeira-execução)
  - [Após a configuração](#após-a-configuração)
  - [Configuração personalizada](#configuração-personalizada)
    - [Personalize o conteúdo do docker-compose](#personalize-o-conteúdo-do-docker-compose)
    - [PHP](#php)
  - [Execute o Nextcloud](#execute-o-nextcloud)
  - [Use uma versão específica do Nextcloud](#use-uma-versão-específica-do-nextcloud)
  - [Logs](#logs)

## Configuração do Docker

Você precisa ter, em seu servidor, o Docker instalado. A instalação pode ser feita com um script oficial, seguindo os seguintes passos:
- Baixe o Docker
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
```
- Execute o script
```bash
sh get-docker.sh
```
- Conceda permissões para executar o comando Docker para seu usuário
```bash
sudo usermod -aG docker $USER
```
- Remova o script de instalação
```bash
rm get-docker.sh
```

## Configuração de proxy

Siga as instruções deste repositório:

https://github.com/LibreCodeCoop/nginx-proxy

## Antes da primeira execução

Copie o `.env.example` para `.env` e defina os valores.

```bash
cp .env.example .env
```

| Ambiente | serviço | Descrição |
|-------------|---------|-------|
| [`VIRTUAL_HOST`](https://github.com/nginx-proxy/nginx-proxy#usage) | `web` | Seu domínio |
| [`LETSENCRYPT_HOST`](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/blob/master/docs/Basic-usage.md#step-3---proxyed-containers) | `web` | Seu domínio |
| [`LETSENCRYPT_EMAIL`](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/blob/master/docs/Let's-Encrypt-and-ACME.md#contact-address) | `web` | Seu email de administrador de sistema |
| `NEXTCLOUD_TRUSTED_DOMAINS` | `app` | domínios separados por vírgula. O domínio `web` é obrigatório, adicione seu domínio junto com o domínio `web`. O domínio `web` é o domínio do serviço Nginx. |

> **PS**: A Let's Encrypt só funciona em servidores quando os `VIRTUAL_HOST` e `LETSENCRYPT_HOST` têm um domínio público válido registrado em um servidor DNS. Não tente usá-lo em localhost, não funciona!

Crie uma rede

```bash
docker network create reverse-proxy
```

## Após a configuração

Após concluir a configuração, acesse esta URL: https://seudomínio.tld/settings/admin/overview.

Se for necessário executar algum comando occ, execute da seguinte forma:

```bash
docker compose exec -u www-data app ./occ db:add-missing-indices
docker compose exec -u www-data app ./occ db:convert-filecache-bigint
```

 ## Configuração personalizada

### Personalize o conteúdo do docker-compose

Você pode fazer isso usando variáveis de ambiente e criando um arquivo chamado `docker-compose.override.yml` para adicionar novos serviços.

### Storage primário Garage S3

Use `docker-compose-garages3.yml` quando quiser que o Nextcloud grave os arquivos em um bucket Garage S3 em vez do diretório local `data/`.

O stack espera estes valores em `.env`:

- `GARAGES3_BUCKET`
- `GARAGES3_KEY`
- `GARAGES3_KEY_ID`
- `GARAGES3_SECRET`
- `GARAGES3_HOSTNAME`, com padrão `host.docker.internal`
- `GARAGES3_PORT`, com padrão `3900`
- `GARAGES3_REGION`, com padrão `garage`

Crie o bucket e a chave de acesso no Garage antes de iniciar o Nextcloud com este compose. `GARAGES3_KEY_ID` deve conter o access key ID do Garage usado pelo Nextcloud.

O serviço Garage usa `garage/garage.toml`. Atualize `rpc_secret` antes de usar em ambiente real.

Use `make up-garages3` para subir o Garage e `make bootstrap-garages3` para criar o bucket e a chave de acesso no Garage.
O bootstrap atualiza `.env` com as credenciais geradas do Garage.
Use `make setup-garages3` para executar a configuração completa e aguardar o Nextcloud reportar como instalado.
O stack agora usa PostgreSQL 16. Se você já criou o volume do banco com uma versão major mais antiga, recrie ou migre esse volume uma vez antes de subir o compose atualizado.

Para uma instalação local limpa, use `make reset-garages3`.
Use `make setup-garages3` se quiser manter o estado local existente e apenas repetir as etapas de setup.

Fluxo básico:

1. Copie `.env.example` para `.env`, se necessário.
2. Atualize `garage/garage.toml` e substitua o `rpc_secret` placeholder.
3. Execute `make setup-garages3`.
4. Abra a URL do Nextcloud e finalize a configuração inicial do admin, se ainda estiver pendente.

### PHP

- Crie seu arquivo `.ini` na pasta `volumes/php/`. Exemplo: `volumes/php/xdebug.ini`
- Altere o arquivo `docker-compose.override.yml` adicionando seu volume
```yaml
services:
  app:
    volumes:
      - ./volumes/php/xdebug.ini:/usr/local/etc/php/conf.d/xdebug.ini
```

## Execute o Nextcloud

```bash
# O serviço postgres é executado separadamente para que seja possível reutilizar este serviço para outras aplicações que usam PostgreSQL
docker compose up -f docker-compose-postgres.yml -d
docker compose up -d
docker compose -d
```
## Use uma versão específica do Nextcloud

Altere o valor de `NEXTCLOUD_VERSION` no arquivo `.env` e coloque o nome do rótulo que deseja usar. Verifique as tags disponíveis aqui: https://hub.docker.com/_/nextcloud/tags

Construa as imagens, derrube os contêineres e inicie-os novamente:

```bash
docker compose build --pull
docker compose up -d
```

## Logs

Se você quiser ver os logs, execute:

```bash
docker compose logs -f --tail=100
```
Você verá esta mensagem nos logs e muitas outras mensagens de atualização:

```log
app_1      | 2020-04-28T19:49:38.568623133Z Inicializando o Nextcloud 18.0.4.2 ...
app_1      | 2020-04-28T19:49:38.577733913Z Atualizando o Nextcloud a partir da versão 18.0.3.0 ...
```
