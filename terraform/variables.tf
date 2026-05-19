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

variable "firebase_project_id" {
  description = "Firebase project ID (visible en la consola de Firebase)"
  type        = string
}

variable "firebase_service_account_json" {
  description = "Contenido JSON completo del service account de Firebase (una sola línea)"
  type        = string
  sensitive   = true
}

variable "google_places_api_key" {
  description = "API Key de Google Places"
  type        = string
  sensitive   = true
}

variable "mapbox_access_token" {
  description = "Access token de Mapbox"
  type        = string
  sensitive   = true
}
