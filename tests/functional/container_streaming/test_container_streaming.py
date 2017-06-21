# coding: utf-8
import random
import tarfile
from io import BytesIO
import itertools
import json
import string
import unittest

import requests
from oio import ObjectStorageApi
from tests.utils import BaseTestCase


def random_container(pfx=""):
    return '{0}content-{1}'.format(pfx, random.randint(0, 65536))


def gen_data(size):
    with open("/dev/urandom", "rb") as rand:
        return rand.read(size)


def gen_names():
    index = 0
    for c0 in "01234567":
        for c1 in "01234567":
            i, index = index, index + 1
            yield i, '{0}/{1}/plop'.format(c0, c1)


# random selection from http://www.columbia.edu/~fdc/utf8/
CHARSET = [
    "طوقونمز",
    "ᛖᚴ ᚷᛖᛏ ᛖᛏᛁ",
    "शक्नोम्यत्तुम्",
    "يؤلمني",
    "က္ယ္ဝန္‌တော္‌",
    "私はガ",
    "yishą́ągo",
    ]

def rand_byte(n):
    return ''.join([chr(random.randint(32, 255)) for i in xrange(n)])

def rand_str(n):
    return ''.join([random.choice(string.ascii_letters) for i in xrange(n)])

def rand_charset(_):
    return random.choice(CHARSET)

def gen_charset_names():
    index = 0
    for c0 in "01234567":
        for c1 in "01234567":
            i, index = index, index + 1
            yield i, '{0}/{1}/plop'.format(c0, random.choice(CHARSET))

def gen_byte_names():
    index = 0
    for c0 in "01234567":
        for c1 in "01234567":
            i, index = index, index + 1
            yield i, '{0}/{1}/plop'.format(c0, rand_byte(10))

def gen_metadata():
    name = rand_str(20)
    value = rand_str(100)
    return (name, value)

def gen_byte_metadata():
    name = rand_str(20)
    value = rand_byte(100)
    return (name, value)

def gen_charset_metadata():
    name = random.choice(CHARSET)
    value = random.choice(CHARSET)
    return (name, value)


# class TestContainerDownload(TestCase):
class TestContainerDownload(BaseTestCase):

    def setUp(self):
        super(TestContainerDownload, self).setUp()
        # FIXME: should we use direct API from BaseTestCase or still container.client ?
        self.conn = ObjectStorageApi(self.ns)
        self._streaming = 'http://' + self.get_service_url('admin')[2] + '/'
        self._cnt = random_container()
        self._uri = self._streaming + 'v1.0/dump?acct=' + self.account + '&ref=' + self._cnt
        self._data = {}
        self.conn.container_create(self.account, self._cnt)
        self.raw = ""

    def tearDown(self):
        for name in self._data:
            self.conn.object_delete(self.account, self._cnt, name)
        self.conn.container_delete(self.account, self._cnt)
        super(TestContainerDownload, self).tearDown()

    def _create_data(self, name=gen_names, metadata=None):
        for idx, name in itertools.islice(name(), 5):
            data = gen_data(513 * idx)
            entry = {'data': data, 'meta': None}
            self.conn.object_create(self.account, self._cnt, obj_name=name, data=data)
            if metadata:
                key, val = metadata()
                entry['meta'] = {key: val}
                self.conn.object_update(self.account, self._cnt, name, entry['meta'])
            self._data[name] = entry

    def _simple_download(self, name=gen_names, metadata=None):
        self._create_data(name, metadata)

        ret = requests.get(self._uri)
        self.assertGreater(len(ret.content), 0)
        self.assertEqual(ret.status_code, 200)
        self.raw = ret.content

        raw = BytesIO(ret.content)
        tar = tarfile.open(fileobj=raw)
        info = self._data.keys()
        for entry in tar.getnames():
            self.assertIn(entry, info)

            tmp = tar.extractfile(entry)
            self.assertEqual(self._data[entry]['data'], tmp.read())
            info.remove(entry)

        self.assertEqual(len(info), 0)
        return tar

    def _check_metadata(self, tar):
        for entry in tar.getnames():
            headers = tar.getmember(entry).pax_headers
            for key, val in self._data[entry]['meta'].items():
                key = u"SCHILY.xattr.user." + key.decode('utf-8')
                self.assertIn(key, headers)
                self.assertEqual(val.decode('utf-8'), headers[key])

    def test_missing_container(self):
        ret = requests.get(self._streaming + random_container("ms-"))
        self.assertEqual(ret.status_code, 404)

    def test_invalid_url(self):
        ret = requests.get(self._streaming)
        self.assertEqual(ret.status_code, 404)

        ret = requests.head(self._streaming + random_container('inv')
                            + '/' + random_container('inv'))
        self.assertEqual(ret.status_code, 404)

    def test_download_empty_container(self):
        ret = requests.get(self._uri)
        self.assertEqual(ret.status_code, 204)

    def test_simple_download(self):
        self._simple_download()

    def test_check_head(self):
        self._create_data()

        get = requests.get(self._uri)
        head = requests.head(self._uri)

        self.assertEqual(get.headers['content-length'], head.headers['content-length'])

    def test_download_per_range(self):
        self._create_data()

        org = requests.get(self._uri)

        data = []
        for idx in xrange(0, int(org.headers['content-length']), 512):
            ret = requests.get(self._uri, headers={'Range': 'bytes=%d-%d' % (idx, idx+511)})
            data.append(ret.content)

        data = "".join(data)
        self.assertGreater(len(data), 0)
        self.assertEqual(org.content, data)

    def test_invalid_range(self):
        self._create_data()

        ranges = ((-512, 511), (512, 0), (1, 3), (98888, 99999))
        for start, end in ranges:
            ret = requests.get(self._uri, headers={'Range': 'bytes=%d-%d' % (start, end)})
            self.assertEqual(ret.status_code, 416, "Invalid error code for range %d-%d" % (start, end))

        ret = requests.get(self._uri, headers={'Range': 'bytes=0-511, 512-1023'})
        self.assertEqual(ret.status_code, 416)

    def test_file_metadata(self):
        tar = self._simple_download(metadata=gen_metadata)
        self._check_metadata(tar)

    def test_container_metadata(self):
        key, val = gen_metadata()
        ret = self.conn.container_update(self.account, self._cnt, {key: val})
        ret = self.conn.container_show(self.account, self._cnt)
        ret = requests.get(self._uri)
        self.assertEqual(ret.status_code, 200)

        raw = BytesIO(ret.content)
        tar = tarfile.open(fileobj=raw)
        self.assertIn(".container_properties", tar.getnames())

        data = json.load(tar.extractfile(".container_properties"))
        self.assertIn(key, data)
        self.assertEqual(val, data[key])

    def test_charset_file(self):
        self._simple_download(name=gen_charset_names)

    @unittest.skip("wip")
    def test_byte_metadata(self):
        self._simple_download(metadata=gen_byte_metadata)
        self._check_metadata(tar)

    def test_charset_metadata(self):
        tar = self._simple_download(metadata=gen_charset_metadata)
        self._check_metadata(tar)