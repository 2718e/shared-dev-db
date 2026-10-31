import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from urllib.parse import urlsplit, unquote

spec = importlib.util.spec_from_file_location('configure', Path(__file__).resolve().parents[1] / 'scripts/configure.py')
configure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configure)


class ConfigurationTests(unittest.TestCase):
    def test_rerun_preserves_credentials_and_private_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            env = Path(directory) / 'config/settings.env'
            self.assertTrue(configure.initialize(env, Path(directory) / 'data'))
            original = env.read_bytes()
            self.assertFalse(configure.initialize(env, Path(directory) / 'other-data'))
            self.assertEqual(original, env.read_bytes())
            self.assertEqual(env.stat().st_mode & 0o777, 0o600)

    def test_existing_data_without_settings_refuses_new_password(self):
        with tempfile.TemporaryDirectory() as directory:
            data = Path(directory) / 'data'
            data.mkdir()
            (data / '18').mkdir()
            env = Path(directory) / 'settings.env'
            with self.assertRaises(ValueError):
                configure.initialize(env, data)
            self.assertFalse(env.exists())

    def test_url_encodes_credentials_and_shell_environment_is_safe(self):
        config = {'services': {'postgres': {
            'environment': {'POSTGRES_USER': 'a@b', 'POSTGRES_PASSWORD': "a:/?#$' b"},
            'ports': [{'target': 5432, 'published': '15432', 'host_ip': '::1'}],
        }}}
        line = configure.connection_environment(config)
        result = subprocess.run(['bash', '-c', line + 'printf %s "$SHARED_DEV_DB_BASE_URL"'],
                                text=True, capture_output=True, check=True)
        url = urlsplit(result.stdout)
        self.assertEqual(unquote(url.username), 'a@b')
        self.assertEqual(unquote(url.password), "a:/?#$' b")
        self.assertEqual(url.hostname, '::1')
        self.assertEqual(url.port, 15432)
        self.assertEqual(url.path, '/')

    @unittest.skipUnless(shutil.which('docker'), 'Docker Compose required')
    def test_real_compose_config_and_existing_data_guard(self):
        with tempfile.TemporaryDirectory() as directory:
            env = Path(directory) / 'settings.env'
            data = Path(directory) / "data with ' quote and \\ slash"
            command = ['python3', str(configure.ROOT / 'scripts/configure.py'), '--env-file', str(env),
                       '--data-dir', str(data), '--require-data-dir']
            # Ignore caller's Compose interpolation overrides.
            clean_env = {k: v for k, v in os.environ.items() if not k.startswith(('POSTGRES_', 'COMPOSE_'))}
            for _ in range(2):
                subprocess.run(command, check=True, capture_output=True, env=clean_env)
            connection = Path(str(env) + '.connection')
            self.assertEqual(connection.stat().st_mode & 0o777, 0o600)
            original = env.read_bytes()
            rejected = subprocess.run(command + ['--data-dir', str(Path(directory) / 'wrong')],
                                      capture_output=True, env=clean_env)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertEqual(env.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
