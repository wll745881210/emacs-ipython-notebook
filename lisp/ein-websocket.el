;;; ein-websocket.el --- Wrapper of websocket.el    -*- lexical-binding:t -*-

;; Copyright (C) 2012- Takafumi Arakaki

;; Author: Takafumi Arakaki <aka.tkf at gmail.com>

;; This file is NOT part of GNU Emacs.

;; ein-websocket.el is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; ein-websocket.el is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with ein-websocket.el.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'websocket)
(require 'ein-core)
(require 'ein-classes)
(require 'url-cookie)
(require 'request)

(declare-function ein:jupyter-crib-token "ein-jupyter")
(declare-function ein:kernel--encode-v1-binary "ein-kernel")

(defun ein:websocket-store-cookie (c host-port url-filename securep)
  (url-cookie-store (car c) (cdr c) nil host-port url-filename securep))

(defun ein:maybe-get-jhconn-user (url)
  (let ((paths (cl-rest (split-string (url-filename (url-generic-parse-url url)) "/"))))
    (when (string= (cl-first paths) "user")
      (list (format "/%s/%s/" (cl-first paths) (cl-second paths))))))

(defun ein:websocket--prepare-cookies (url)
  "Websocket gets its cookies using the url-cookie API, so we need
to transcribe any cookies stored in `request-cookie-alist' during
earlier calls to `request' (request.el)."
  (let* ((parsed-url (url-generic-parse-url url))
         (host-port (format "%s:%s" (url-host parsed-url) (url-port parsed-url)))
         (base-url (file-name-as-directory (url-filename parsed-url)))
         (securep (string-match "^wss://" url))
         (read-cookies-func (lambda (path)
                              (request-cookie-alist
                               (url-host parsed-url) path securep)))
         (cookies (cl-loop
                   repeat 4
                   for cand = (cl-mapcan read-cookies-func
                                         `("/"
                                           "/hub/"
                                           ,base-url
                                           ,@(ein:maybe-get-jhconn-user url)))
                   until (cl-some (lambda (x) (string= "_xsrf" (car x))) cand)
                   do (ein:log 'info
                        "ein:websocket--prepare-cookies: no _xsrf among %s, retrying."
                        cand)
                   do (sleep-for 0 300)
                   finally return cand)))
    (dolist (c cookies)
      (ein:websocket-store-cookie
       c host-port (car (url-path-and-query parsed-url)) securep))))

(defun ein:websocket (url kernel on-message on-close on-open)
  (ein:websocket--prepare-cookies (ein:$kernel-ws-url kernel))
  (let* ((ew (make-ein:$websocket :ws nil :kernel kernel :closed-by-client nil))
         (v1-protos '("v1.kernel.websocket.jupyter.org"))
         (try-v1 (>= (ein:$kernel-api-version kernel) 3)))
      (cl-labels ((do-connect (protos)
                  (setf (ein:$websocket-v1-protocol ew) (if protos t nil))
                  (let ((ws (apply #'websocket-open url
                                   (append
                                    (when protos
                                      (list :protocols protos))
                                    (list :on-open
                                          (lambda (w)
                                            (if (eql (websocket-ready-state w) 'open)
                                                (funcall on-open w)
                                              (when protos
                                                (ein:log 'info
                                                  "WS: v1 protocol rejected, retrying without")
                                                (do-connect nil))))
                                          :on-message on-message
                                          :on-close
                                          (lambda (w)
                                            (unless protos
                                              (when (eq w (ein:$websocket-ws ew))
                                                (funcall on-close w))))
                                          :on-error
                                          (lambda (ws action err)
                                            (ein:log 'info
                                              "WS action [%s] %s (%s)"
                                              err action
                                              (websocket-url ws))))))))
                    (setf (ein:$websocket-ws ew) ws)
                    (setf (websocket-client-data ws) ew))))
      (do-connect (when try-v1 v1-protos))
      ew)))

(defun ein:websocket-open-p (websocket)
  (eql (websocket-ready-state (ein:$websocket-ws websocket)) 'open))


(defun ein:websocket-send (websocket text)
  ;;  (ein:log 'info "WS: Sent message %s" text)
  (condition-case-unless-debug err
      (websocket-send-text (ein:$websocket-ws websocket) text)
    (error (message "Error %s on sending websocket message %s." err text))))

(defun ein:websocket-send-binary (kernel msg)
  "Send MSG as a v1 binary frame on KERNEL's websocket.
MSG is a plist with :header, :parent_header, :metadata, :content, :channel."
  (let* ((channel (or (plist-get msg :channel) "shell"))
         (header-json (ein:json-encode (plist-get msg :header)))
         (parent-json (ein:json-encode (or (plist-get msg :parent_header)
                                           (make-hash-table))))
         (metadata-json (ein:json-encode (or (plist-get msg :metadata)
                                             (make-hash-table))))
         (content-json (ein:json-encode (or (plist-get msg :content)
                                            (make-hash-table))))
         (binary-data (ein:kernel--encode-v1-binary
                       channel header-json parent-json metadata-json content-json))
         (ws (ein:$kernel-websocket kernel)))
     (ein:log 'debug "WS: sending binary ch=%s msg-type=%s (%d bytes)"
              channel (plist-get (plist-get msg :header) :msg_type)
              (length binary-data))
     (websocket-send (ein:$websocket-ws ws)
                    (make-websocket-frame :opcode 'binary
                                          :payload binary-data
                                          :completep t))))


(defun ein:websocket-close (websocket)
  (setf (ein:$websocket-closed-by-client websocket) t)
  (websocket-close (ein:$websocket-ws websocket)))


(defun ein:websocket-send-shell-channel (kernel msg)
  (cond ((= (ein:$kernel-api-version kernel) 2)
         (ein:websocket-send
          (ein:$kernel-shell-channel kernel)
          (ein:json-encode msg)))
        ((ein:$websocket-v1-protocol (ein:$kernel-websocket kernel))
         (ein:websocket-send-binary kernel (plist-put msg :channel "shell")))
         (t
          (ein:websocket-send-binary kernel (plist-put msg :channel "shell")))))

(defun ein:websocket-send-stdin-channel (kernel msg)
  (cond ((= (ein:$kernel-api-version kernel) 2)
         (ein:log 'warn "Stdin messages only supported with IPython 3."))
        ((ein:$websocket-v1-protocol (ein:$kernel-websocket kernel))
         (ein:websocket-send-binary kernel (plist-put msg :channel "stdin")))
        (t
         (ein:websocket-send-binary kernel (plist-put msg :channel "stdin")))))

(provide 'ein-websocket)

;;; ein-websocket.el ends here
