"""Copy one member of a ZIP archive at a URL, with HTTP range requests.

Usage: zip_member.py URL MEMBER OUTPUT

Only the central directory and the member come over the network.
"""

import io
import shutil
import sys
import urllib.request
import zipfile

url, member, output = sys.argv[1:]


class HttpFile(io.RawIOBase):
    def __init__(self, url):
        # ci.android.com answers HEAD with 404 and redirects GET. Follow the
        # redirect one time, not for each range.
        request = urllib.request.Request(url, headers={"Range": "bytes=0-0"})
        with urllib.request.urlopen(request) as response:
            self.url = response.geturl()
            self.size = int(response.headers["Content-Range"].rsplit("/", 1)[1])
        self.position = 0

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=io.SEEK_SET):
        base = {io.SEEK_SET: 0, io.SEEK_CUR: self.position, io.SEEK_END: self.size}[whence]
        self.position = base + offset
        return self.position

    def readinto(self, buffer):
        if self.position >= self.size:
            return 0
        end = min(self.position + len(buffer), self.size) - 1
        request = urllib.request.Request(
            self.url, headers={"Range": f"bytes={self.position}-{end}"}
        )
        with urllib.request.urlopen(request) as response:
            data = response.read()
        buffer[: len(data)] = data
        self.position += len(data)
        return len(data)


archive = zipfile.ZipFile(io.BufferedReader(HttpFile(url), buffer_size=8 << 20))
with archive.open(member) as source, open(output, "wb") as target:
    shutil.copyfileobj(source, target, 8 << 20)
