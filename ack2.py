from __future__ import print_function

from contextlib import closing
from time import sleep
import os
import argparse
import json
import sys

try:
    from urllib import request
    URLError = request.URLError
except ImportError:
    import urllib2 as request
    URLError = IOError


def vw_request(url, data=None):
    req = request.Request(
        url,
        headers={'Content-Type': 'application/json'} if data else {},
        data=data and json.dumps(data).encode('utf-8'),
    )

    print("Request:", url)
    with closing(request.urlopen(req)) as req:
        if req.getcode() != 200:
            raise ValueError("Status code is {}".format(req.getcode()))
        return json.loads(req.read().decode('utf-8'))


def parse_environ(env):
    if 'LITHOS_NAME' in env:
        mode = 'ack'
        role, process = env["LITHOS_NAME"].split("/", 1)
        if process.startswith("cmd."):
            mode = 'cmd'
            process = process[4:]
        process = next(iter(process.rsplit('.', 1)))
        if process.endswith("-1") or process.endswith("-2"):
            process = process[:-2]
        group, name = process.rsplit('-', 1)
        return {
            "role": role,
            "group": group,
            "step": "cmd_" + name,
        }, mode
    else:
        return {
            "role": "example-role",
            "group": "example-group",
            "step": "cmd_example_step",
        }, "warn"


def check_pending(prefix, action_id):
    while True:
        try:
            actions = vw_request(prefix + "/v1/pending_actions")
            if not str(action_id) in actions:
                return True
            else:
                sleep(1)
        except (ValueError, URLError) as e:
            print("Error checking pending actions", e, file=sys.stderr)
            return False


def main():

    ap = argparse.ArgumentParser()
    ap.add_argument("--proceed", action="store_true",
                    help="Execute proceed action instead of ack. \
                          (useful to proceed actions marked as `manual`)")
    ap.add_argument("--error", help="Acknowledge step with error message")
    ap.add_argument("--verwalter-host", default="localhost",
                    help="Initial verwalter host (default %(default)s)")
    ap.add_argument("--verwalter-port", default=8379, type=int,
                    help="Verwalter port (default %(default)s)")
    options = ap.parse_args()
    params, mode = parse_environ(os.environ)

    if options.error:
        action = {
            "button": {
                "role": params['role'],
                "group": params['group'],
                "action": "update_action",
                "update_action": "error",
                "step": params['step'],
                "error_message": options.error,
            },
        }
    else:
        action = {
            "button": {
                "role": params['role'],
                "group": params['group'],
                "action": "update_action",
                "update_action": "proceed" if options.proceed else "ack",
                "step": params['step'],
            },
        }

    if mode == 'warn':
        print("No environ found. To ack manually run:", file=sys.stderr)
        print("  curl http://leader-name:8379/v1/action "
              "-H 'Content-Type: application/json' -XPOST -d",
              "'" + json.dumps(action) + "'", file=sys.stderr)
        sys.exit(77)
    elif mode == 'cmd':
        print("It looks like you're running command manually. To ack run:",
              file=sys.stderr)
        print("  curl http://leader-name:8379/v1/wait_action "
              "-H 'Content-Type: application/json' -XPOST -d",
              "'" + json.dumps(action) + "'",
              file=sys.stderr)
        sys.exit(0)

    while True:
        url = "http://{0.verwalter_host}:{0.verwalter_port}".format(options)
        try:
            data = vw_request(url + '/v1/status')
            leader_host = data['leader']['name']
        except (KeyError, ValueError, URLError) as e:
            print("Error getting leader", e, file=sys.stderr)
            sleep(1)
            continue

        url = "http://{1}:{0.verwalter_port}".format(options, leader_host)

        print("Acking with params", action)
        try:
            response = vw_request(url + '/v1/wait_action', data=action)
        except (KeyError, ValueError, URLError) as e:
            print("Error executing action", e, file=sys.stderr)
            sleep(1)
            continue
        else:
            print("Response: ", response or '<empty>')

        break

    # Everything is fine, just sleep until the process is killed
    print("Done, waiting to be killed")
    sleep(86400)


if __name__ == '__main__':
    main()
