# El Security Group actúa como firewall a nivel de instancia.
# Define qué tráfico entra (ingress) y qué tráfico sale (egress).
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-sg-ec2"
  description = "Security group para la instancia EC2 de Rideglory"
  vpc_id      = aws_vpc.main.id

  # ── Reglas de ENTRADA ───────────────────────────────────────────────────────

  # SSH: solo desde tu IP. Nunca abrir 22 a 0.0.0.0/0 en producción.
  ingress {
    description = "SSH desde tu IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  # HTTP API: el api-gateway es el único servicio público.
  ingress {
    description = "API Gateway HTTP"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ── Reglas de SALIDA ────────────────────────────────────────────────────────
  # Permitir todo el tráfico saliente: necesario para git clone, npm install,
  # llamadas a Firebase, etc.
  egress {
    description = "Salida total permitida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"   # -1 significa "todos los protocolos"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg-ec2"
    Project = var.project_name
    Owner   = var.github_user
  }
}