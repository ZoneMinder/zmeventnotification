# A very simple client that shows you how 
# you can control the ES with the new control interface

# Note: This is a simple synchronous script. 
# read https://github.com/websocket-client/websocket-client for advanced usage
# requires websocket_client library


import json
import time
import sys

try:
    from websocket import create_connection
except ImportError:
    print ("""
            websocket client is missing. 
            sudo -H pip install websocket_client
           """)
    exit(1)


# restarts the ES, waits 10 secs and relogin
def restart():
    global ws
    send_command(cmd='restart')
    ws.close()
    print ('Waiting 10s for server to restart...\n')
    time.sleep(10)
    ws = create_connection(URL)
    login()

def edit():
    key = input ('key:')
    val = input ('value:')
    send_command(cmd='edit', key=key, val=val)

# generic function to send multiple commands
def send_command(cmd=None, key=None, val=None):
    payload = { "event":"escontrol",
                "data": {
                "command":cmd,
        
                }
            }

    if (cmd == 'edit' and key and val):
        payload["data"]["key"] = key
        payload["data"]["val"] = val

    if (cmd in ['mute','unmute']):
        monstr = input ('Enter list of monitor IDs separated by commas or ENTER for all: ')
        if not monstr:
           pass
        else:
            f=[int(i.strip()) for i in monstr]
            payload["data"]["monitors"] = f
           
    payloadstr = json.dumps(payload)
    print ("Sending: {}".format(payloadstr))
    ws.send(payloadstr)
    result =  ws.recv()
    print("Received {}\n".format(result))
    

# logs into ES with control channel
def login():
    payloadstr=json.dumps({"event":"auth", "category":"escontrol", "data": {"password":CONTROLPASSWD}})
    print ("Sending: {}".format(payloadstr))
    ws.send(payloadstr)
    result =  ws.recv()
    print("Received {}\n".format(result))
    rjson = json.loads(result)
    if rjson.get('status') != "Success":
        print ("Login Error")
        exit()

# quits script
def terminate():
    global ws
    ws.close()
    print ('Bye\n')
    exit(0)

# MAIN

if  len(sys.argv) != 3:
    print ("\n Format: {} wss://ESserver:port/ password\n".format(sys.argv[0]))
    exit(1)

URL = sys.argv[1]
CONTROLPASSWD = sys.argv[2]

ws = create_connection(URL)
login()

functions = {
        '1': lambda: login(),
        '2': lambda: send_command(cmd='get'),
        '3':lambda: send_command(cmd='mute'),
        '4': lambda:send_command(cmd='unmute'),
        '5': lambda:restart(),
        '6': lambda:send_command(cmd='reset'),
        '7': lambda: edit(),
        '8': lambda:terminate()
        }

while True:
    print ("""
        Choose Options
        ==============
        1. Re-Login
        2. Get settings
        3. Mute notifications
        4. Unmute notifications
        5. restart ES
        6. reset admin commands
        7. edit
        8. Exit
    """)
    i = input ("Select a choice:")
    functions[i]()
