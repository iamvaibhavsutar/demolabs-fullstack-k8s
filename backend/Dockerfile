# ---------- Stage 1: build with Maven ----------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build

# Copy pom.xml first so Docker can cache the dependency layer separately
# from source code changes (faster rebuilds).
COPY pom.xml .
RUN mvn -B dependency:go-offline

COPY src ./src
RUN mvn -B clean package -DskipTests

# ---------- Stage 2: minimal runtime image ----------
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Run as non-root (required by most prod PodSecurity "restricted" policies)
RUN addgroup -S spring && adduser -S spring -G spring
USER spring:spring

COPY --from=build /build/target/demolabs-backend.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
