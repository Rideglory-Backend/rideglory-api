resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.key_pair_name

  # Disco raíz: 20 GB de tipo gp3 (Free Tier cubre hasta 30 GB total).
  # gp3 es más moderno que gp2: 3000 IOPS base sin costo extra.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.disk_size_gb
    delete_on_termination = true   # Borra el disco al terminar la instancia
    encrypted             = false  # Para MVP no es necesario
  }

  # User Data: script Bash que se ejecuta UNA SOLA VEZ al primer arranque.
  # Aquí instalamos Docker, clonamos repos y levantamos los servicios.
  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    github_user                   = var.github_user
    postgres_password             = var.postgres_password
    project_name                  = var.project_name
    firebase_project_id           = var.firebase_project_id
    firebase_service_account_json = var.firebase_service_account_json
    mapbox_access_token           = var.mapbox_access_token
  })

  # Espera que los health checks del estado de instancia pasen antes de
  # marcar el recurso como creado en Terraform.
  # Esto no garantiza que Docker esté listo, solo que la instancia arrancó.
  tags = {
    Name    = "${var.project_name}-app-server"
    Project = var.project_name
    Owner   = var.github_user
  }
}