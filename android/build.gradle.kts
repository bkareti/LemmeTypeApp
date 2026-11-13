import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension

plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}

// Shared settings for the pure-Kotlin core modules: JVM 21 bytecode, warnings are errors,
// JUnit 5, and the repository's shared/fixtures folder handed to tests.
subprojects {
    pluginManager.withPlugin("org.jetbrains.kotlin.jvm") {
        extensions.configure<JavaPluginExtension> {
            sourceCompatibility = JavaVersion.VERSION_21
            targetCompatibility = JavaVersion.VERSION_21
        }
        extensions.configure<KotlinJvmProjectExtension> {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_21)
                allWarningsAsErrors.set(true)
            }
        }
        tasks.withType<Test>().configureEach {
            useJUnitPlatform()
            systemProperty("lemmetype.fixtures", rootDir.resolve("../shared/fixtures").canonicalPath)
            testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
        }
    }
}

// Core modules must stay free of Android, networking, and desktop UI imports, like Swift `Domain` (ADR 0035).
val coreSources = fileTree(rootDir) { include("core-*/src/main/**/*.kt") }
val androidRoot: File = rootDir
val checkCoreImports =
    tasks.register("checkCoreImports") {
        description = "Fails if a core module imports android.*, androidx.*, java.net, or javax.swing."
        inputs.files(coreSources)
        val sources = coreSources
        val root = androidRoot
        doLast {
            val banned = Regex("""^import\s+(android\.|androidx\.|java\.net\.|javax\.swing\.)""", RegexOption.MULTILINE)
            val offenders = sources.files.filter { banned.containsMatchIn(it.readText()) }
            if (offenders.isNotEmpty()) {
                throw GradleException("Banned imports in core modules: " + offenders.joinToString { it.relativeTo(root).path })
            }
        }
    }

tasks.register("check") {
    group = "verification"
    description = "Every core check: compile with warnings as errors, unit tests, and the import rule."
    dependsOn(checkCoreImports, subprojects.map { "${it.path}:check" })
}
