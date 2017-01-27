#!/opt/anaconda/bin/python

import sys
import os
import unittest
import string
from StringIO import StringIO

# Simulating the Runtime environment
os.environ['TMPDIR'] = '/tmp'
os.environ['_CIOP_APPLICATION_PATH'] = '/application'
os.environ['ciop_job_nodeid'] = 'dummy'
os.environ['ciop_wf_run_root'] = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'artifacts')

class NodeATestCase(unittest.TestCase):

    def setUp(self):
        pass

    def test_log(self):
        self.assertEqual(1, 1)

if __name__ == '__main__':
    unittest.main()
