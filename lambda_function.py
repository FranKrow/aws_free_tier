import json

def lambda_handler(event, context):
    # Log the received event for debugging purposes
    print("Received event:", json.dumps(event, indent=2))
    
    # Extract the message from the event
    message = event.get('message', 'No message provided')
    
    # Create a response
    response = {
        'statusCode': 200,
        'body': json.dumps({
            'message': f"Hello from Lambda! You sent: {message}"
        })
    }
    
    return response