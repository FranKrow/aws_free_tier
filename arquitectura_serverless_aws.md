# Resumen y Guía de Arquitectura Serverless en AWS con Terraform

Este documento detalla el paso a paso de la infraestructura como código (IaC) desplegada en AWS utilizando Terraform, enfocada en mantenerse dentro del **AWS Free Tier**, orientada a eventos y completamente serverless.

---

## 1. Diagrama de Arquitectura del Sistema

![](architecture.png)

---

## 2. Descripción Detallada de los Componentes y el Código Terraform

### A. Configuración de Terraform y Proveedor AWS
```hcl
terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 5.0"
        }
    }
}

provider "aws" {
    region = "us-east-1"
}
```
* **Qué hace:** Define la versión requerida del proveedor de AWS (~> 5.0) y establece la región predeterminada (`us-east-1`) donde se crearán todos los recursos.
* **Por qué se agrega así:** Garantiza la compatibilidad de sintaxis y recursos entre diferentes entornos, fijando una región específica para evitar costos imprevistos o discrepancias de disponibilidad.
* **Qué pasaría si no se agrega:** Terraform fallaría al intentar inicializar el proyecto por falta de definición del proveedor, o crearía recursos en regiones por defecto no deseadas.

---

### B. Tabla de Base de Datos NoSQL (DynamoDB)
```hcl
resource "aws_dynamodb_table" "main_table" {
    name           = "my-dynamodb-table"
    billing_mode   = "PAY_PER_REQUEST" 
    hash_key       = "ID"

    attribute {
        name = "ID"
        type = "S"
    }
}
```
* **Qué hace:** Crea una tabla NoSQL en DynamoDB llamada `my-dynamodb-table` con el modo de cobro bajo demanda (`PAY_PER_REQUEST`) y una clave de partición primaria `ID` de tipo String (`S`).
* **Por qué se agrega así:** El modo `PAY_PER_REQUEST` (Serverless/On-Demand) es ideal para el AWS Free Tier porque no requiere aprovisionar capacidad fija de lectura/escritura (RCU/WCU), pagando únicamente por las operaciones reales ejecutadas (dentro de los límites gratuitos mensuales).
* **Qué pasaría si no se agrega:** No tendrías una base de datos persistente para almacenar registros o estados generados por las peticiones de la función Lambda.

---

### C. Cola de Mensajes (Amazon SQS)
```hcl
resource "aws_sqs_queue" "main_queue" {
    name = "my-sqs-queue"
}
```
* **Qué hace:** Crea una cola de mensajes estándar en Amazon SQS llamada `my-sqs-queue`.
* **Por qué se agrega así:** Permite desacoplar arquitecturas basadas en eventos, permitiendo que la Lambda envíe mensajes a la cola para su procesamiento asíncrono posterior sin bloquear al cliente HTTP.
* **Qué pasaría si no se agrega:** La infraestructura perdería la capacidad de procesamiento asíncrono de mensajes en cola.

---

### D. Rol de IAM y Permisos de Ejecución
```hcl
resource "aws_iam_role" "lambda_role" {
    name = "lambda_execution_role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Principal = {
                    Service = "lambda.amazonaws.com"
                }
            },
        ]
    })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
```
* **Qué hace:** Crea un rol de IAM (`lambda_execution_role`) que permite explícitamente al servicio Lambda asumir dicho rol, y le adjunta la política administrada `AWSLambdaBasicExecutionRole`.
* **Por qué se agrega así:** Por seguridad, AWS bloquea por defecto cualquier acción de sus servicios. Este rol otorga los permisos mínimos indispensables para que la función pueda ejecutarse y escribir sus registros de depuración (`print()`) en Amazon CloudWatch Logs.
* **Qué pasaría si no se agrega:** La función Lambda fallaría inmediatamente al invocarse por falta de credenciales/permisos, y no generaría logs de diagnóstico.

---

### E. Empaquetado Automático del Código Lambda
```hcl
data "archive_file" "lambda_zip" {
    type        = "zip"
    source_file = "lambda_function.py"  
    output_path = "lambda_function_payload.zip"
}
```
* **Qué hace:** Lee localmente el archivo de código fuente `lambda_function.py` y lo comprime automáticamente en un archivo ZIP (`lambda_function_payload.zip`).
* **Por qué se agrega así:** AWS Lambda requiere que el código fuente se suba en formato comprimido (ZIP). Automatizarlo con Terraform evita tener que empaquetar manualmente el archivo cada vez que se actualiza el código.
* **Qué pasaría si no se agrega:** Terraform no tendría el artefacto binario requerido para desplegar o actualizar el código de la función Lambda.

---

### F. Función AWS Lambda
```hcl
resource "aws_lambda_function" "my_lambda" {
    filename         = "lambda_function_payload.zip"
    function_name    = "my_lambda_function" 
    role             = aws_iam_role.lambda_role.arn
    handler          = "lambda_function.lambda_handler" 
    runtime          = "python3.9" 

    source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}
```
* **Qué hace:** Despliega la función serverless en Python 3.9 (`my_lambda_function`), vinculándola al rol de IAM, especificando el manejador (`lambda_handler`) dentro del código y controlando cambios mediante el hash del archivo ZIP.
* **Por qué se agrega así:** Es el núcleo computacional de la arquitectura encargada de procesar la lógica de negocio ante cada evento recibido.
* **Qué pasaría si no se agrega:** No existiría el motor computacional para procesar peticiones web ni eventos del sistema.

---

### G. API Gateway (HTTP API) y Despliegue Automático
```hcl
resource "aws_apigatewayv2_api" "lambda_api" {
    name          = "my-api-gateway-lambda"
    protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default_stage" {
    api_id      = aws_apigatewayv2_api.lambda_api.id
    name        = "$default"
    auto_deploy = true
}
```
* **Qué hace:** Crea un API Gateway HTTP v2 (`my-api-gateway-lambda`) optimizado para baja latencia y bajo costo, configurando una etapa predeterminada (`$default`) con despliegue automático (`auto_deploy = true`).
* **Por qué se agrega así:** Expone la arquitectura al mundo exterior a través de una URL HTTP pública, permitiendo recibir peticiones web sin administrar servidores web tradicionales (como Nginx o Apache).
* **Qué pasaría si no se agrega:** La función Lambda estaría aislada internamente y ningún cliente externo podría invocarla mediante solicitudes HTTP estándar.

---

### H. Integración y Ruta de API Gateway
```hcl
resource "aws_apigatewayv2_integration" "lambda_integration" {
    api_id           = aws_apigatewayv2_api.lambda_api.id
    integration_type = "AWS_PROXY"
    integration_uri  = aws_lambda_function.my_lambda.invoke_arn
}

resource "aws_apigatewayv2_route" "lambda_route" {
    api_id    = aws_apigatewayv2_api.lambda_api.id
    route_key = "ANY /"
    target   = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}
```
* **Qué hace:** Conecta el API Gateway con la función Lambda mediante el tipo de integración `AWS_PROXY` (que pasa el evento HTTP completo directamente a la función) y configura una ruta genérica (`ANY /`) que captura cualquier método (`GET`, `POST`, etc.) en la raíz.
* **Por qué se agrega así:** Establece el puente directo de comunicación para que cualquier llamada HTTP recibida en el endpoint se redirija de manera transparente a la función Lambda.
* **Qué pasaría si no se agrega:** Aunque el API Gateway existiría, no sabría a dónde enviar las peticiones entrantes, devolviendo errores 404 o de configuración rota.

---

### I. Permisos de Invocación desde API Gateway
```hcl
resource "aws_lambda_permission" "api_gateway_permission" {
    statement_id  = "AllowExecutionFromAPIGateway"
    action          = "lambda:InvokeFunction"
    function_name   = aws_lambda_function.my_lambda.function_name
    principal       = "apigateway.amazonaws.com"
    source_arn      = "${aws_apigatewayv2_api.lambda_api.execution_arn}/*/*"
}
```
* **Qué hace:** Concede el permiso explícito en la política de recursos de Lambda para que el servicio API Gateway pueda invocar la función.
* **Por qué se agrega así:** Por defecto, Lambda rechaza invocaciones externas incluso si están conectadas mediante una integración en API Gateway. Este recurso desbloquea esa autorización de seguridad.
* **Qué pasaría si no se agrega:** Al intentar acceder a la URL del API Gateway, el sistema arrojará un error `502 Bad Gateway` o `Internal Server Error` porque Lambda denegará la ejecución solicitada por API Gateway.

---

### J. Output del Endpoint del API Gateway
```hcl
output "api_gateway_endpoint" {
    value = aws_apigatewayv2_api.lambda_api.api_endpoint
    description = "The endpoint of the API Gateway that triggers the Lambda function."
}
```
* **Qué hace:** Imprime en la consola de Terraform la URL pública final del API Gateway tras un despliegue exitoso (`terraform apply`).
* **Por qué se agrega así:** Facilita al usuario obtener de forma inmediata el enlace exacto para hacer pruebas mediante herramientas como `curl` o el navegador.
* **Qué pasaría si no se agrega:** El despliegue funcionaría igual, pero tendrías que buscar manualmente la URL del API Gateway navegando por la consola web de AWS.

---

## 3. Descripción del Flujo Principal de Ejecución

1. **Recepción de la Petición:** Un cliente (como `curl` o un navegador web) realiza una solicitud HTTP a la URL pública proporcionada por el **API Gateway HTTP** (`api_gateway_endpoint`).
2. **Enrutamiento e Integración:** El API Gateway captura la solicitud mediante la ruta `ANY /` y, gracias a la integración `AWS_PROXY`, empaqueta todos los detalles de la petición en un objeto JSON estándar.
3. **Invocación Segura:** Utilizando los permisos concedidos por `aws_lambda_permission`, el API Gateway invoca a la función **AWS Lambda** (`my_lambda_function`).
4. **Ejecución y Registro:** La función Lambda procesa el evento en Python 3.9. Durante su ejecución, imprime mensajes informativos mediante `print()`, los cuales son capturados y almacenados de forma automática en **Amazon CloudWatch Logs** gracias al rol de IAM (`AWSLambdaBasicExecutionRole`).
5. **Respuesta:** La función Lambda devuelve una respuesta HTTP formateada que el API Gateway reenvía de vuelta al cliente original.
