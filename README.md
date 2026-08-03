# Infraestructura de Monitoreo Automatizada con Ansible y Grafana

## Objetivo

El objetivo de este proyecto es automatizar el despliegue de una infraestructura de monitoreo utilizando Ansible como herramienta de Infrastructure as Code (IaC).

El proyecto permite desplegar servicios basados en Docker, configurar herramientas de monitoreo y habilitar alertas en Grafana mediante notificaciones por correo electrónico utilizando SMTP de Gmail.

La finalidad principal es crear una infraestructura reproducible, donde los componentes puedan ser configurados y desplegados de manera consistente mediante automatización, aplicando buenas prácticas de DevOps como gestión de configuración, manejo seguro de secretos y automatización de procesos.

---

## Tecnologías utilizadas

- **Ansible** - Automatización de configuración y despliegue de infraestructura.
- **Ubuntu 24.04 LTS** - Sistema operativo utilizado como ambiente de ejecución.
- **Docker** - Plataforma de contenedores.
- **Docker Compose** - Herramienta para la definición y ejecución de servicios en contenedores.
- **Grafana** - Visualización de métricas, dashboards y configuración de alertas.
- **Prometheus** - Recolección y consulta de métricas del sistema y aplicaciones.
- **GitHub** - Control de versiones y almacenamiento del código fuente.
- **GitHub Actions** - Automatización de procesos CI/CD.
- **Ansible Vault** - Protección y cifrado de información sensible.

## Otros

- Python
- Bash scripting
- SMTP Gmail para envío de alertas

---

# Flujo del proyecto

## 0. Host prerequisites

El runner necesita una instancia de Ubuntu en WSL. Desde PowerShell como administrador:

```powershell
wsl --install -d Ubuntu-24.04
```

Después de reiniciar Windows, abre Ubuntu e instala Git y Ansible:

```bash
sudo apt update
sudo apt install -y ansible git
```

Los demás pasos se ejecutan dentro de Ubuntu, desde el checkout del proyecto.

## 1. Environment setup

Para evitar problemas de compatibilidad con la administración de paquetes de Python, se utilizó Ubuntu 24.04 como distribución principal.

Antes de ejecutar el despliegue, se deben configurar las variables de ambiente necesarias:

```bash
# Ejecutar desde la carpeta ansible/
export ANSIBLE_CONFIG="$PWD/ansible.cfg"
export RUNNER_PAT="YOUR_GITHUB_TOKEN"
export DOCKER_CLIENT_TIMEOUT=600
export COMPOSE_HTTP_TIMEOUT=600
```

El token puede ser un fine-grained PAT con permiso **Administration: Read and write** sobre este repositorio. No se debe guardar el token en el repositorio.

## 2. Ansible Configuration

El proyecto utiliza roles de Ansible para separar responsabilidades y mantener una estructura modular.

Estructura principal:

<img width="350" height="797" alt="image" src="https://github.com/user-attachments/assets/98782618-b00d-414c-96e4-b33e7223863d" />
<img width="351" height="522" alt="image" src="https://github.com/user-attachments/assets/c7a45461-ed96-4522-bdc8-10482ee471d9" />

Las variables fueron separadas de la siguiente manera:

- **vars.yml:** Contiene variables generales de configuración del proyecto.
- **vault.yml:** Contiene información sensible como contraseñas y credenciales cifradas mediante Ansible Vault.

La carpeta all dentro de group_vars permite que Ansible cargue automáticamente ambos archivos durante la ejecución del playbook.

## 3. Docker-Python Compatibility Issues

Durante el despliegue se presentó un problema relacionado con las restricciones de instalación de paquetes Python en Ubuntu 24.04 (PEP 668).

Para solucionarlo se realizaron los siguientes cambios:

### Rol Docker

Archivo modificado:
```
roles/docker/tasks/main.yml
```

Se eliminó la opción de abajo de los comandos de instalación de paquetes Python.
```
--break-system-packages
```

## Grafana Gmail Alert Configuration

Para habilitar notificaciones por correo electrónico se configuró SMTP utilizando Gmail.

Pasos realizados:

1. Crear una cuenta de correo dedicada para las alertas de monitoreo.
2. Activar autenticación de dos factores (2FA).
3. Crear una contraseña de aplicación desde Google App Passwords.
4. Configurar las variables SMTP dentro de Grafana.
5. Guardar las credenciales utilizando Ansible Vault.

Configuración agregada en:
```
roles/grafana/tasks/main.yml
```

Variables SMTP:
```YAML
# Configuración SMTP para alertas por correo
GF_SMTP_ENABLED: "true"
GF_SMTP_HOST: "smtp.gmail.com:587"
GF_SMTP_USER: "{{ grafana_smtp_user }}"
GF_SMTP_PASSWORD: "{{ grafana_smtp_password }}"
GF_SMTP_FROM_ADDRESS: "{{ grafana_smtp_user }}"
GF_SMTP_FROM_NAME: "Grafana Alerts"
```

### Secrets Management

Las credenciales SMTP fueron almacenadas utilizando Ansible Vault.

Crear archivo:
```Bash
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
```

Cifrar el archivo:
```Bash
ansible-vault encrypt group_vars/all/vault.yml
```

Para desplegar la infraestructura:
```Bash
ansible-playbook site.yml -K --ask-vault-pass
```

### Grafana Alert Rules

Después del despliegue:

1. Ingresar a la interfaz web de Grafana.
2. Crear un Contact Point utilizando correo electrónico.
3. Crear una regla de alerta.
4. Configurar:
- Consulta de métricas (Query).
- Condición de evaluación.
- Threshold o límite para activar la alerta.
- Método de notificación.

Ejemplo:
```
Generar una alerta cuando la cantidad de solicitudes a una API supere un límite establecido:
```

## GitHub Actions Self-Hosted Runner

Durante la implementación inicial, el workflow de GitHub Actions quedaba detenido en:

```text
Waiting for a runner to pick up this job...
```

El primer enfoque utilizaba la imagen myoung34/github-runner, pero el registro del runner presentaba problemas durante la configuración dentro del contenedor. Para tener mayor control sobre el entorno de ejecución, se reemplazó la imagen existente por una imagen personalizada basada en Ubuntu, construida dentro del proyecto.

La imagen personalizada se construye mediante:
```
ansible/roles/github_runner/files/
├── Dockerfile.runner
└── entrypoint.sh
```

Los cambios realizados fueron:

Se modificó el archivo *Dockerfile.runner* para crear una imagen personalizada basada en Ubuntu que incluye:
- GitHub Actions Runner.
- Ansible.
- Docker CLI.
- Dependencias necesarias para ejecutar el runner.
Se creó el archivo *entrypoint.sh*, encargado de:
- Obtener el token temporal de registro del runner.
- Configurar automáticamente el runner en el repositorio de GitHub.
- Iniciar el servicio del runner para recibir jobs.
Se actualizaron las variables utilizadas en el role de Ansible del GitHub runner (*github_runner.yml*) para adaptarlas a la nueva configuración del runner personalizado.

### Install/Repair Runners

La reparación del runner se debe iniciar una vez de forma local en WSL. Un runner desconectado no puede ejecutar el workflow que lo repararía.

```bash
cd ansible
export ANSIBLE_CONFIG="$PWD/ansible.cfg"
export RUNNER_PAT="YOUR_GITHUB_TOKEN"
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory.ini runner.yml --ask-become-pass
```

Si `group_vars/all/vault.yml` está cifrado, agrega `--ask-vault-pass` al último comando. Para confirmar que quedó conectado:

```bash
docker ps --filter name=github-runner
docker logs --tail 100 github-runner
```

El log debe terminar indicando que el runner está escuchando trabajos. También debe aparecer como **Idle** en *Settings > Actions > Runners* del repositorio.
Después de recuperar el runner, cancela manualmente las ejecuciones antiguas que sigan en cola y vuelve a ejecutar solamente la más reciente.

## Addendum

***Docker Containers***
<img width="1104" height="213" alt="image" src="https://github.com/user-attachments/assets/c9cb67f1-58e9-4380-871e-cea7a2141330" />

***Alert Rules > Evaluation Group***
<img width="1171" height="844" alt="image" src="https://github.com/user-attachments/assets/d159059d-3db5-420e-beaa-ea5840402543" />

***Grafana Alerts > Normal*** (1min evaluation interval)
<img width="1904" height="844" alt="image" src="https://github.com/user-attachments/assets/2090f886-2ced-4705-ae40-3eaa4224eb1e" />

***Metrics Traffic***
<img width="1098" height="617" alt="image" src="https://github.com/user-attachments/assets/74f351cd-1c6f-4e7b-a562-5ac725d38d94" />

***Prometheus Querying Interface***
<img width="1911" height="745" alt="image" src="https://github.com/user-attachments/assets/5fa74281-008b-4a70-b678-5fa5d130a09b" />

***Grafana Alerts > Pending*** (5m pending period)
<img width="1908" height="844" alt="image" src="https://github.com/user-attachments/assets/46d15180-c676-4a85-add2-6fdf31f20eaf" />

***Grafana Alerts > Firing***
<img width="1909" height="842" alt="image" src="https://github.com/user-attachments/assets/af7930b8-9302-4de9-834f-e496a045dd8a" />

***GMAIL Notification***
<img width="1910" height="980" alt="image" src="https://github.com/user-attachments/assets/25dadb83-536b-452d-afaf-0a9e9eab600b" />
<img width="1914" height="980" alt="image" src="https://github.com/user-attachments/assets/82c825c8-b6e5-4607-924a-1d93bc67d211" />

***Self-hosted runners***
<img width="1910" height="983" alt="image" src="https://github.com/user-attachments/assets/7e334805-718f-4561-aa77-1e89fa3b6e5d" />

***Deploy***
<img width="1913" height="984" alt="image" src="https://github.com/user-attachments/assets/b2be2e0f-cce6-4552-9de0-be992ef0e689" />

