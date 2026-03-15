FROM clojure:temurin-21-tools-deps

WORKDIR /app

COPY deps.edn .
RUN clojure -P

COPY src src
COPY resources resources

ENV DATABASE_PATH=data/kadi.db

EXPOSE 3000

CMD ["clojure", "-J-Xmx384m", "-M:run"]
