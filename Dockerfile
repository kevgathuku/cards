FROM cimg/clojure:1.11.2-openjdk-21.0-node

WORKDIR /app

COPY deps.edn .
RUN clj -P

COPY src src
COPY resources resources

EXPOSE 3000

CMD ["clj", "-M:run"]
