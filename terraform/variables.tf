variable "aws_region" {
  description = "Región de AWS donde se desplegará la infraestructura"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en los tags"
  type        = string
  default     = "rideglory"
}

variable "key_pair_name" {
  description = "Nombre del Key Pair de EC2 creado en el tutorial 01-aws-setup"
  type        = string
  default     = "rideglory-key"
}

variable "your_ip" {
  description = "Tu IP pública para restringir acceso SSH. Formato: x.x.x.x/32"
  type        = string
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t2.micro"   # Elegible para Free Tier
}

variable "disk_size_gb" {
  description = "Tamaño del disco EBS en GB (Free Tier incluye 30 GB)"
  type        = number
  default     = 20
}

variable "github_user" {
  description = "Usuario de GitHub donde están los repositorios"
  type        = string
}

variable "postgres_password" {
  description = "Contraseña de PostgreSQL"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub Personal Access Token con permisos read:org y contents:read para clonar repos privados de Rideglory-Backend"
  type        = string
  sensitive   = true
}
