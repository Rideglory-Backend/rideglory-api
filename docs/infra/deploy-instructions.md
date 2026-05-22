Prompt de Instrucciones para Claude Code: Infraestructura Rideglory-Backend
Contexto del Proyecto
Estás trabajando en el ecosistema Rideglory-Backend, una arquitectura de microservicios basada en NestJS. El objetivo es desplegar la aplicación en AWS utilizando la capa gratuita (Free Tier) de forma agresiva para mantener costos en $0 durante la fase de desarrollo y MVP. Utiliza los agentes necesarios para esto.
.
Repositorios involucrados:
api-gateway
users-ms
vehicles-ms
events-ms
maintenances-ms
contracts (Librería/Contratos)
common-lib (Librería compartida)
Estrategia de Optimización de Costos (MVP)
Para evitar cargos, no utilizaremos servicios gestionados costosos inicialmente
:
Cómputo: Una única instancia Amazon EC2 (t2.micro o t3.micro) que ejecutará todos los servicios.
Base de Datos: No usar Amazon RDS. Desplegar una imagen de PostgreSQL 15-alpine dentro del mismo Docker Compose
.
Registro de Imágenes: No usar Amazon ECR para evitar cargos de almacenamiento. El despliegue se hará clonando los repositorios directamente en la EC2 o mediante despliegue remoto
.
Secretos: No usar AWS Secrets Manager. Utilizar archivos .env gestionados localmente en la instancia
.
Tareas Técnicas Requeridas
1. Estandarización de Dockerfiles
Construye o actualiza los Dockerfile de cada microservicio siguiendo estas mejores prácticas de producción
:
Multi-stage builds: Separar la etapa de build de la de runtime para minimizar el tamaño de la imagen.
Imágenes base ligeras: Usar node:22-alpine
.
Seguridad: Configurar el contenedor para que corra como un usuario no-root (USER node)
.
Higiene: Incluir un script de healthcheck.js externo para monitoreo
.
2. Orquestación con Docker Compose Unificado
Crea un archivo docker-compose.yml que orqueste todos los servicios en la misma red bridge
.
Límites de Memoria (Crítico): Dado que la EC2 gratuita solo tiene 1GB de RAM, debes asignar límites estrictos (mem_limit) a cada contenedor (ej. 128MB por microservicio y 256MB para la DB) para evitar que la instancia se bloquee
.
Persistencia: Configurar volúmenes de Docker para que los datos de PostgreSQL no se pierdan al reiniciar contenedores
.
Dependencias: Asegurar que los servicios esperen a la base de datos (depends_on).
3. Infraestructura como Código (Terraform)
Crea scripts de Terraform para automatizar la creación de la infraestructura base
:
VPC y Networking: Configurar una VPC básica con subredes públicas y un Security Group que solo abra los puertos necesarios (puerto 3000 para el api-gateway y 22 para SSH).
Instancia EC2: Definir una instancia dentro de la capa gratuita.
User Data Script: Incluir un script de Bash que se ejecute al iniciar la máquina para instalar Docker, Docker Compose y clonar los repositorios necesarios
.
4. Configuración de Entorno
Implementar una validación de variables de entorno en NestJS usando ConfigModule y Joi para asegurar que el sistema no arranque si faltan credenciales críticas
.
Resultado Esperado
Los Dockerfile optimizados para cada microservicio.
El docker-compose.yml unificado con límites de recursos.
Los archivos .tf de Terraform para levantar la instancia EC2.
Un script de Bash (deploy.sh) que automatice todo el proceso de levantamiento en el servidor
.