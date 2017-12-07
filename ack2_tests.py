import unittest
import ack2

class TestParseLithosName(unittest.TestCase):

    def test_parse_daemon(self):
        vals, mode = ack2.parse_environ({
            "LITHOS_NAME": "my-app-staging/myapp-migrate-2.0",
        })
        self.assertEqual(mode, "ack")
        self.assertEqual(vals, {
            "role": "my-app-staging",
            "group": "myapp",
            "step": "cmd_migrate",
        })

    def test_more_dashes(self):
        vals, mode = ack2.parse_environ({
            "LITHOS_NAME": "my-app-staging/ru-slave-migrate-2.0",
        })
        self.assertEqual(mode, "ack")
        self.assertEqual(vals, {
            "role": "my-app-staging",
            "group": "ru-slave",
            "step": "cmd_migrate",
        })

    def test_parse_command(self):
        vals, mode = ack2.parse_environ({
            "LITHOS_NAME": "my-app-staging/cmd.myapp-migrate-2.1235",
        })
        self.assertEqual(mode, "cmd")
        self.assertEqual(vals, {
            "role": "my-app-staging",
            "group": "myapp",
            "step": "cmd_migrate",
        })

    def test_parse_empty(self):
        vals, mode = ack2.parse_environ({ })
        self.assertEqual(mode, "warn")
        self.assertEqual(vals, {
            "role": "example-role",
            "group": "example-group",
            "step": "cmd_example_step",
        })
