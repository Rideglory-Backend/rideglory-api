# ─── VPC ─────────────────────────────────────────────────────────────────────
# Una VPC es la red privada virtual donde vivirán todos los recursos.
# El bloque 10.0.0.0/16 da hasta 65,536 IPs internas.
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true   # Permite nombres DNS para instancias EC2
  enable_dns_support   = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
    Owner   = var.github_user
  }
}

# ─── Subnet pública ──────────────────────────────────────────────────────────
# Una subnet pública tiene ruta directa al internet gateway.
# Usamos solo una subnet (en una sola AZ) para simplificar el MVP.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"   # 256 IPs disponibles
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true   # La EC2 recibe IP pública automáticamente

  tags = {
    Name    = "${var.project_name}-subnet-public"
    Project = var.project_name
    Owner   = var.github_user
  }
}

# ─── Internet Gateway ─────────────────────────────────────────────────────────
# Permite que los recursos de la VPC se comuniquen con internet.
# Sin IGW, la EC2 no puede hacer git clone ni recibir tráfico externo.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
    Owner   = var.github_user
  }
}

# ─── Route Table ──────────────────────────────────────────────────────────────
# Define las reglas de enrutamiento de la subnet.
# La ruta 0.0.0.0/0 → IGW significa: "todo el tráfico externo va al internet gateway".
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "${var.project_name}-rt-public"
    Project = var.project_name
    Owner   = var.github_user
  }
}

# ─── Asociación Route Table ↔ Subnet ─────────────────────────────────────────
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}