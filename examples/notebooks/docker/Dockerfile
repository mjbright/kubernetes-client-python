FROM nbgallery/jupyter-alpine:latest 

RUN pip install git+https://github.com/kubernetes-client/python.git
RUN pip install pick ppretty

WORKDIR /root/

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["jupyter", "notebook", "--ip=0.0.0.0", "--allow-root", "--no-browser"]

