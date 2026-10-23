# Implantação e personalização

Este guia explica o ambiente Docker Compose fornecido pelo repositório. A configuração padrão **utiliza as imagens publicadas pela LibreCode no GHCR**: `app` e `cron` compartilham uma imagem de aplicação versionada, enquanto `web` utiliza a imagem publicada do Nginx. Os mantenedores ainda podem utilizar os comandos específicos para builds locais.

Volte para a [apresentação do projeto](README_ptBR.md) ou consulte as [tags das imagens publicadas](images.md).

## Pré-requisitos

Instale o Docker Engine e o plugin Docker Compose. Consulte a [documentação oficial](https://docs.docker.com/engine/install/).

A instalação padrão pressupõe um domínio público, um proxy reverso responsável pelo HTTPS (por exemplo, o [nginx-proxy da LibreCode](https://github.com/LibreCodeCoop/nginx-proxy)) e duas redes externas do Docker:

```bash
docker network create reverse-proxy
docker network create postgres
```

Crie essas redes **uma única vez**, caso ainda não existam. Configure separadamente o proxy, o DNS e a integração com Let's Encrypt. Para obter um certificado TLS público, você precisa de um domínio resolvível publicamente; o Let's Encrypt não emite certificados para localhost.

## Configuração do ambiente

```bash
cp .env.example .env
```

Edite o `.env` antes de iniciar os serviços. Informe, no mínimo, as credenciais do administrador, a senha do banco e o domínio público. O exemplo seleciona `stable-fpm`, que acompanha a versão principal aprovada mais recente; fixe uma tag de versão principal suportada antes da implantação em produção para evitar atualizações inesperadas.

| Variável | Finalidade |
| --- | --- |
| `NEXTCLOUD_VERSION` | Tag da **imagem de aplicação publicada pela LibreCode no GHCR** para `app` e `cron`; padrão `stable-fpm` (móvel); utilize uma tag de versão principal em produção |
| `VIRTUAL_HOST`, `LETSENCRYPT_HOST` | Domínio público utilizado pelo proxy |
| `LETSENCRYPT_EMAIL` | E-mail de contato para os certificados |
| `NEXTCLOUD_TRUSTED_DOMAINS` | Domínios confiáveis, incluindo o domínio público e o host interno `web`, quando aplicável |
| `NEXTCLOUD_ADMIN_USER`, `NEXTCLOUD_ADMIN_PASSWORD` | Credenciais do administrador inicial |
| `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` | Nome, usuário e senha do banco de dados |
| `POSTGRES_HOST` | Host do banco; o padrão na extensão Compose é `postgres` |
| `TZ` | Fuso horário dos contêineres |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE` | Configurações do servidor de envio de e-mail |
| `SMTP_NAME`, `SMTP_PASSWORD`, `SMTP_AUTHTYPE` | Autenticação de e-mail, quando necessária |
| `MAIL_FROM_ADDRESS`, `MAIL_DOMAIN` | Endereço do remetente |

Consulte `docker-compose.yml` e `.env.example` para verificar as variáveis usadas pelo ambiente.

## Iniciar o Nextcloud

A configuração padrão combina o Compose principal com a extensão do PostgreSQL:

```bash
docker compose -f docker-compose.yml -f docker-compose-postgres.yml pull
docker compose -f docker-compose.yml -f docker-compose-postgres.yml up -d
```

O Compose principal contém Nextcloud FPM, Nginx, Redis e cron. A extensão adiciona o PostgreSQL e conecta os serviços da aplicação e do cron à rede do banco.

**Compatibilidade do banco:** o arquivo `docker-compose-postgres.yml` ainda utiliza `postgres:11-alpine`, versão que não recebe mais manutenção. Esse é um exemplo legado, não uma recomendação para produção. Para produção, escolha uma versão do PostgreSQL ainda suportada e compatível com o Nextcloud e planeje a migração dos volumes existentes. Não altere simplesmente a versão principal do PostgreSQL mantendo um diretório de dados antigo. O exemplo Garage S3 usa PostgreSQL 16 de forma independente.

Após a configuração, abra `https://seu-dominio.example/settings/admin/overview` para consultar a visão administrativa.

Para executar comandos de manutenção, utilize o usuário do servidor web:

```bash
docker compose -f docker-compose.yml -f docker-compose-postgres.yml \
  exec -u www-data app php occ status
```

## Escolher e atualizar a versão do Nextcloud

Altere `NEXTCLOUD_VERSION` no arquivo `.env` para escolher uma tag publicada da imagem de aplicação da LibreCode, utilizada por `app` e `cron`. Essa variável **não define** quais versões são construídas e publicadas pela LibreCode no GHCR.

```bash
docker compose -f docker-compose.yml -f docker-compose-postgres.yml pull app cron web
docker compose -f docker-compose.yml -f docker-compose-postgres.yml up -d
```

Faça backup do banco de dados, da configuração e dos arquivos persistidos antes de atualizar. Confira as exigências de compatibilidade do Nextcloud: downgrade ou saltos não suportados entre versões podem impedir o uso dos dados. Prefira atualizações de versões principais planejadas.

Consulte a [política de tags e atualizações](images.md) antes de mudar de versão principal ou utilizar digests OCI imutáveis.

## Armazenamento primário opcional com Garage S3

O arquivo `docker-compose-garages3.yml` oferece um exemplo separado em que o Nextcloud utiliza o Garage para armazenar os arquivos, em vez do diretório de dados local. Esse ambiente possui seu próprio PostgreSQL 16.

Configure no `.env`:

- `GARAGES3_BUCKET`, `GARAGES3_KEY_ID`, `GARAGES3_SECRET`
- `GARAGES3_HOSTNAME` (padrão `host.docker.internal`) e `GARAGES3_PORT` (padrão `3900`)
- `GARAGES3_REGION` (padrão `garage`) e as opções de TLS e acesso por caminho, quando necessárias

Substitua o valor de exemplo de `rpc_secret` em `garage/garage.toml`. Crie o bucket e a chave de acesso do Nextcloud ou utilize os comandos de preparação do projeto:

```bash
make up-garages3
make bootstrap-garages3
make setup-garages3
```

O bootstrap pode atualizar o `.env` com as credenciais geradas. Revise os efeitos antes de executá-lo em uma instalação existente. Não mude o armazenamento primário de um ambiente em produção sem um plano de migração.

## Personalização avançada

Utilize `docker-compose.override.yml` para acrescentar serviços ou personalizar os existentes. Por exemplo, para carregar um arquivo de configuração do PHP:

```yaml
services:
  app:
    volumes:
      - ./volumes/php/custom.ini:/usr/local/etc/php/conf.d/custom.ini:ro
```

As configurações do PHP-FPM também podem ser montadas em `/usr/local/etc/php-fpm.d/`. Verifique a compatibilidade com a versão do PHP utilizada pelo Nextcloud.

## Logs e solução de problemas

```bash
docker compose -f docker-compose.yml -f docker-compose-postgres.yml logs -f --tail=100
```

Para comandos de desenvolvimento, consulte o [NCDD](ncdd.md). Para serviços de chamada e conferência, veja o [Nextcloud Talk](https://github.com/LibreCodeCoop/nextcloud-docker-talk).
