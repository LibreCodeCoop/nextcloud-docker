# Setup NextCloud

Este projeto cria uma instância no Docker do NextCloud para ambientes locais contendo:

- HTTPS, utilizando o [mkcert](https://github.com/FiloSottile/mkcert);
- em português;
- com um banco PostgreSQL;
- com um usuário administrador;
- com os aplicativos Deck, Calendar e Contacts;
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
