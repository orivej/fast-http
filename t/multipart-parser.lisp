(in-package :cl-user)
(defpackage fast-http-test.multipart-parser
  (:use :cl
        :fast-http
        :fast-http.multipart-parser
        :fast-http.parser
        :fast-http-test.test-utils
        :prove)
  (:import-from :cl-utilities
                :collecting
                :collect))
(in-package :fast-http-test.multipart-parser)

(syntax:use-syntax :interpol)

(plan nil)

(defun test-ll-parser (boundary body expected &optional description)
  (let ((parser (make-ll-multipart-parser :boundary boundary))
        results
        headers)
    (http-multipart-parse parser
                          (make-ll-callbacks
                           :header-field (lambda (parser data start end)
                                           (declare (ignore parser))
                                           (push (cons (babel:octets-to-string data :start start :end end)
                                                       nil)
                                                 headers))
                           :header-value (lambda (parser data start end)
                                           (declare (ignore parser))
                                           (setf (cdr (car headers))
                                                 (append (cdr (car headers))
                                                         (list (babel:octets-to-string data :start start :end end)))))
                           :body (lambda (parser data start end)
                                   (declare (ignore parser))
                                   (push
                                    (list :headers
                                          (loop for (key . values) in (nreverse headers)
                                                append (list key (apply #'concatenate 'string values)))
                                          :body
                                          (babel:octets-to-string data :start start :end end))
                                    results)
                                   (setf headers nil)))
                          body)
    (is (nreverse results) expected description)))

(test-ll-parser "AaB03x"
                (bv (str #?"--AaB03x\r\n"
                         #?"Content-Disposition: form-data; name=\"field1\"\r\n"
                         #?"\r\n"
                         #?"Joe Blow\r\nalmost tricked you!\r\n"
                         #?"--AaB03x\r\n"
                         #?"Content-Disposition: form-data; name=\"pics\"; filename=\"file1.txt\"\r\n"
                         #?"Content-Type: text/plain\r\n"
                         #?"\r\n"
                         #?"... contents of file1.txt ...\r\r\n"
                         #?"--AaB03x--\r\n"))
                '((:headers ("Content-Disposition" "form-data; name=\"field1\"")
                   :body #?"Joe Blow\r\nalmost tricked you!")
                  (:headers ("Content-Disposition" "form-data; name=\"pics\"; filename=\"file1.txt\""
                             "Content-Type" "text/plain")
                   :body #?"... contents of file1.txt ...\r"))
                "rfc1867")

(let ((big-content (make-string (* 1024 3) :initial-element #\a)))
  (test-ll-parser "---------------------------186454651713519341951581030105"
                  (bv (str #?"-----------------------------186454651713519341951581030105\r\n"
                           #?"Content-Disposition: form-data; name=\"file1\"; filename=\"random.png\"\r\n"
                           #?"Content-Type: image/png\r\n"
                           #?"\r\n"
                           big-content #?"\r\n"
                           #?"-----------------------------186454651713519341951581030105\r\n"
                           #?"Content-Disposition: form-data; name=\"file2\"; filename=\"random.png\"\r\n"
                           #?"Content-Type: image/png\r\n"
                           #?"\r\n"
                           big-content big-content #?"\r\n"
                           #?"-----------------------------186454651713519341951581030105--\r\n"))
                  `((:headers ("Content-Disposition" "form-data; name=\"file1\"; filename=\"random.png\""
                                                     "Content-Type" "image/png")
                     :body ,big-content)
                    (:headers ("Content-Disposition" "form-data; name=\"file2\"; filename=\"random.png\""
                                                     "Content-Type" "image/png")
                     :body ,(concatenate 'string big-content big-content)))
                  "big file"))

(test-ll-parser "---------------------------186454651713519341951581030105"
                (bv (str #?"-----------------------------186454651713519341951581030105\r\n"
                         #?"Content-Disposition: form-data; name=\"name\"\r\n"
                         #?"Content-Type: text/plain\r\n"
                         #?"\r\n"
                         #?"深町英太郎\r\n"
                         #?"-----------------------------186454651713519341951581030105\r\n"
                         #?"Content-Disposition: form-data; name=\"introduce\"\r\n"
                         #?"Content-Type: text/plain\r\n"
                         #?"\r\n"
                         #?"Common Lispが好きです。好きな関数はconsです。\r\n"
                         #?"-----------------------------186454651713519341951581030105--\r\n"))
                '((:headers ("Content-Disposition" "form-data; name=\"name\""
                             "Content-Type" "text/plain")
                   :body "深町英太郎")
                  (:headers ("Content-Disposition" "form-data; name=\"introduce\""
                             "Content-Type" "text/plain")
                   :body "Common Lispが好きです。好きな関数はconsです。"))
                "UTF-8")

(test-ll-parser "---------------------------186454651713519341951581030105"
                (bv (str #?"-----------------------------186454651713519341951581030105\r\n"
                         #?"Content-Disposition: form-data;\r\n"
                         #?"\tname=\"file1\"; filename=\"random.png\"\r\n"
                         #?"Content-Type: image/png\r\n"
                         #?"\r\n"
                         #?"abc\r\n"
                         #?"-----------------------------186454651713519341951581030105\r\n"
                         #?"Content-Disposition: form-data;\r\n"
                         #?" name=\"text\"\r\n"
                         #?"\r\n"
                         #?"Test text\n with\r\n ümläuts!\r\n"
                         #?"-----------------------------186454651713519341951581030105--\r\n"))
                '((:headers ("Content-Disposition" #?"form-data;\tname=\"file1\"; filename=\"random.png\""
                             "Content-Type" "image/png")
                   :body "abc")
                  (:headers ("Content-Disposition" "form-data; name=\"text\"")
                   :body #?"Test text\n with\r\n ümläuts!"))
                "multiline header value")


(defun test-parser (content-type data expected &optional description)
  (is (collecting
        (let ((parser (make-multipart-parser content-type
                                             (lambda (field-name headers field-meta body)
                                               (collect (list field-name
                                                              headers
                                                              field-meta
                                                              (babel:octets-to-string body)))))))
          (funcall parser data)))
      expected
      description))

(test-parser "multipart/form-data; boundary=AaB03x"
             (bv (str #?"--AaB03x\r\n"
                      #?"Content-Disposition: form-data; name=\"field1\"\r\n"
                      #?"\r\n"
                      #?"Joe Blow\r\nalmost tricked you!\r\n"
                      #?"--AaB03x\r\n"
                      #?"Content-Disposition: form-data; name=\"pics\"; filename=\"file1.txt\"\r\n"
                      #?"Content-Type: text/plain\r\n"
                      #?"\r\n"
                      #?"... contents of file1.txt ...\r\r\n"
                      #?"--AaB03x--\r\n"))
             '(("field1"
                (:content-disposition "form-data; name=\"field1\"")
                (:name "field1")
                #?"Joe Blow\r\nalmost tricked you!")
               ("pics"
                (:content-disposition "form-data; name=\"pics\"; filename=\"file1.txt\""
                 :content-type "text/plain")
                (:name "pics"
                 :filename "file1.txt")
                #?"... contents of file1.txt ...\r"))
             "rfc1867")

(let ((big-content (make-string (* 1024 3) :initial-element #\a)))
  (test-parser "multipart/form-data; boundary=\"---------------------------186454651713519341951581030105\""
               (bv (str #?"-----------------------------186454651713519341951581030105\r\n"
                        #?"Content-Disposition: form-data; name=\"file1\"; filename=\"random.png\"\r\n"
                        #?"Content-Type: image/png\r\n"
                        #?"\r\n"
                        big-content #?"\r\n"
                        #?"-----------------------------186454651713519341951581030105\r\n"
                        #?"Content-Disposition: form-data; name=\"file2\"; filename=\"random.png\"\r\n"
                        #?"Content-Type: image/png\r\n"
                        #?"\r\n"
                        big-content big-content #?"\r\n"
                        #?"-----------------------------186454651713519341951581030105--\r\n"))
               `(("file1"
                  (:content-disposition "form-data; name=\"file1\"; filename=\"random.png\""
                   :content-type "image/png")
                  (:name "file1" :filename "random.png")
                  ,big-content)
                 ("file2"
                  (:content-disposition "form-data; name=\"file2\"; filename=\"random.png\""
                   :content-type "image/png")
                  (:name "file2" :filename "random.png")
                  ,(concatenate 'string big-content big-content)))
               "big file"))

(test-parser "multipart/form-data; boundary=\"---------------------------186454651713519341951581030105\""
             (bv (str #?"-----------------------------186454651713519341951581030105\r\n"
                      #?"Content-Disposition: form-data; name=\"name\"\r\n"
                      #?"Content-Type: text/plain\r\n"
                      #?"\r\n"
                      #?"深町英太郎\r\n"
                      #?"-----------------------------186454651713519341951581030105\r\n"
                      #?"Content-Disposition: form-data; name=\"introduce\"\r\n"
                      #?"Content-Type: text/plain\r\n"
                      #?"\r\n"
                      #?"Common Lispが好きです。好きな関数はconsです。\r\n"
                      #?"-----------------------------186454651713519341951581030105--\r\n"))
             '(("name"
                (:content-disposition "form-data; name=\"name\""
                 :content-type "text/plain")
                (:name "name")
                "深町英太郎")
               ("introduce"
                (:content-disposition "form-data; name=\"introduce\""
                 :content-type "text/plain")
                (:name "introduce")
                "Common Lispが好きです。好きな関数はconsです。"))
             "UTF-8")

(test-parser "multipart/form-data; boundary=\"---------------------------186454651713519341951581030105\""
             (bv (str #?"-----------------------------186454651713519341951581030105\r\n"
                      #?"Content-Disposition: form-data;\r\n"
                      #?"\tname=\"file1\"; filename=\"random.png\"\r\n"
                      #?"Content-Type: image/png\r\n"
                      #?"\r\n"
                      #?"abc\r\n"
                      #?"-----------------------------186454651713519341951581030105\r\n"
                      #?"Content-Disposition: form-data;\r\n"
                      #?" name=\"text\"\r\n"
                      #?"\r\n"
                      #?"Test text\n with\r\n ümläuts!\r\n"
                      #?"-----------------------------186454651713519341951581030105--\r\n"))
             '(("file1"
                (:content-disposition #?"form-data;\tname=\"file1\"; filename=\"random.png\""
                 :content-type "image/png")
                (:name "file1" :filename "random.png")
                "abc")
               ("text"
                (:content-disposition "form-data; name=\"text\"")
                (:name "text")
                #?"Test text\n with\r\n ümläuts!"))
             "multiline header value")

(finalize)