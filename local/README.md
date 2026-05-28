# Setup NextCloud

Este projeto cria uma instância no Docker do NextCloud para ambientes locais contendo:

- HTTPS, utilizando o [mkcert](https://github.com/FiloSottile/mkcert);
- em português;
- com um banco PostgreSQL;
- com um usuário administrador;
- com o sistema de cron habilitado;

## Setup inicial

Para rodar o projeto pela primeira vez, crie um arquivo `.env` com base no `.env.dist` adaptando as variaveis de acordo com seu cenário. As variáveis disponiveis são:

|         Variável          |             Default              |                     Descrição                      |
| ------------------------- | -------------------------------- | -------------------------------------------------- |
| POSTGRES_PASSWORD         | SECRET_PASSWORD                  | senha do banco                                     |
| POSTGRES_DB               | nextcloud                        | nome do banco                                      |
| POSTGRES_USER             | nextcloud                        | usuário do banco                                   |
| NEXTCLOUD_ADMIN_USER      | admin                            | username do primeiro administrador do NextCloud    |
| NEXTCLOUD_ADMIN_PASSWORD  | admin                            | username do primeiro administrador do NextCloud    |
| NEXTCLOUD_TRUSTED_DOMAINS | mydomain.coop                    | dominio local da aplicação                         |
| CA_STORE                  | /usr/local/share/ca-certificates | diretório dos certificados, de acordo com a distro |

Caso a distribuição usada não seja Debian ou Ubuntu, é necessário informar outro diretório na variável `CA_STORE`, para uma correta geração dos certificados pelo `mkcert` . O diretório default para a maioria das distribuições pode ser verificado na [página do projeto](https://github.com/aegypius/mkcert-for-nginx-proxy#for-ubuntu--debian)

Também é necessário adicionar o dominio customizado de acordo com o que foi informado em `NEXTCLOUD_TRUSTED_DOMAINS`. Isso pode ser feito adicionando a linha abaixo ao arquivo `/etc/hosts` da máquina:

```bash
0.0.0.0 mydomain.coop
```

Realizado as etapas acima, basta rodar o Makefile, o que pode ser feito executando o comando `make` na raiz do projeto:

## Stack local com Garage S3

Se você quiser testar o Nextcloud localmente usando o Garage como storage primário, use o compose dedicado:

```bash
cp .env.dist .env
make reset-garages3
```

Se você quiser reaproveitar o estado local existente em vez de apagar tudo, use:

```bash
make setup-garages3
```

Essa variante:

- expõe o Nextcloud em `http://localhost:8080`
- sobe o Garage junto com o banco e o cron
- usa o Garage em modo single-node para funcionar localmente
- aplica automaticamente o layout do Garage para permitir bucket/key com um nó
- cria automaticamente o bucket e a key do Garage
- grava o access key ID em `GARAGES3_KEY_ID` e o secret em `GARAGES3_SECRET`
- usa o arquivo `../volumes/nextcloud/config/s3.config.php` para o object store
- `make reset-garages3` faz a limpeza e reinstala tudo do zero

Se o `garage/garage.toml` ainda estiver com `rpc_secret` placeholder, o bootstrap substitui o valor antes de subir o daemon.
Se você já tiver iniciado esse stack com PostgreSQL 12, precisará recriar ou migrar o volume de banco uma vez para o PostgreSQL 16.
