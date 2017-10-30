from __future__ import print_function

from contextlib import closing
from time import sleep
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
    req = request.Request(url,
                          data=data and json.dumps(data).encode('utf-8'))

    print("Request:", url)
    with closing(request.urlopen(req)) as req:
        if req.getcode() != 200:
            raise ValueError("Status code is {}".format(req.getcode()))
        return json.loads(req.read().decode('utf-8'))


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
    ap.add_argument("role", help="Role to acknowledge")
    ap.add_argument("group", help="Group to acknowledge")
    ap.add_argument("step", help="Step to acknowledge")
    ap.add_argument("--proceed", action="store_true",
                    help="Execute proceed action instead of ack. \
                          (useful to proceed actions marked as `manual`)")
    ap.add_argument("--error", help="Acknowledge step with error message")
    ap.add_argument("--verwalter-host", default="localhost",
                    help="Initial verwalter host (default %(default)s)")
    ap.add_argument("--verwalter-port", default=8379, type=int,
                    help="Verwalter port (default %(default)s)")
    options = ap.parse_args()

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

        if options.error:
            action = {
                "button": {
                    "role": options.role,
                    "group": options.group,
                    "action": "update_action",
                    "update_action": "error",
                    "step": options.step,
                    "error_message": options.error,
                },
            }
        else:
            action = {
                "button": {
                    "role": options.role,
                    "group": options.group,
                    "action": "update_action",
                    "update_action": "proceed" if options.proceed else "ack",
                    "step": options.step,
                },
            }

        try:
            response = vw_request(url + '/v1/action', data=action)
            action_id = response["registered"]
        except (KeyError, ValueError, URLError) as e:
            print("Error executing action", e, file=sys.stderr)
            sleep(1)
            continue

        if not check_pending(url, action_id):
            sleep(1)
            continue

        break

    # Everything is fine, just sleep until the process is killed
    print("Done, waiting to be killed")
    sleep(86400)


if __name__ == '__main__':
    main()
