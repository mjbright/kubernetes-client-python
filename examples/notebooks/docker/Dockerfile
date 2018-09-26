FROM nbgallery/jupyter-alpine:latest 

RUN pip install git+https://github.com/kubernetes-client/python.git
RUN pip install pick ppretty

WORKDIR /root/

RUN mkdir /root/bin
RUN curl -L -o /root/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
RUN chmod +x /root/bin/kubectl

ADD .profile /root/

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["jupyter", "notebook", "--ip=0.0.0.0", "--allow-root"]

