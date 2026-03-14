FROM cimg/clojure:1.11.2-openjdk-21.0-node

WORKDIR /app

COPY deps.edn .
RUN clojure -P

COPY src src
COPY resources resources

EXPOSE 3000

CMD ["clojure", "-M:run"]
