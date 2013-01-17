#!/usr/bin/python
import signal
import urlparse
import random
import time
import re
import smtplib
import sys
import socket
import urllib


try:
    maxTries = 1

    signal.alarm(5*60)


    data = {}
    data['username'] = 'jgross@everyzing.com'
    data['password'] = 'jeffzing'

    data['seriesid'] = '1602807'
    data['guid'] = 'nonexistentitem3949858943'

    datastr = urllib.urlencode(data)
    req = 'POST /hosting/pca/delete HTTP/1.0\r\nHost: dataservices.ramp.com\r\nContent-type: application/x-www-form-urlencoded;charset=UTF-8\r\nContent-length: %d\r\n\r\n%s' % (len(datastr),datastr)


    hosts = [
        'ramp-app-13',
        ]

    goal = 'FAILED'


    def lowLevelHttpWithTimeout(h, req, timeout=30):
        import threading
        class InterruptableThread(threading.Thread):
            def __init__(self):
                threading.Thread.__init__(self)
                self.result = None

            def run(self):
                try:
                    self.result = lowLevelHttp(h,req)
                except:
                    self.result = None
                    raise

        it = InterruptableThread()
        it.start()
        it.join(timeout)
        if it.isAlive():
            return None
        else:
            return it.result

    def lowLevelHttp(h,req):
        start = time.time()
        s = socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        s.connect((socket.gethostbyname(h),80))
        s.send(req)
        res = ''
        while 1:
            r = s.recv(10000)
            if len(r) == 0:
                break
            res = res+r
        return res




    for h in hosts:
        start = time.time()
        tries = 0

        while tries < maxTries:
          res = lowLevelHttpWithTimeout(h,req,timeout=4)
          res = str(res)

          if res.find(goal) != -1:
            err = None
            break

          badRes = res
          tries = tries+1
        elapsed = time.time()-start
        if tries > 0:
          err = 'Host: %s timed out or returned invalid response: %s' % (h,badRes)

        if err is not None:
          print err
          sys.exit(-1)
        else:
          print 'OK: %s %s %s %s' % (h,elapsed,time.ctime(),res)
          #print 'OK: %s %s %s' % (h,elapsed,time.ctime())
except:
    sys.exit(-1)
    
signal.alarm(1)
