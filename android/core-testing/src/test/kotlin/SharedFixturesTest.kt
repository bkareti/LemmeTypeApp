import com.lemmetype.core.testing.SharedFixtures
import org.junit.jupiter.api.Test
import kotlin.test.assertTrue

class SharedFixturesTest {
    @Test
    fun `every shared fixture is valid JSON`() {
        val files = SharedFixtures.folder.listFiles { file -> file.extension == "json" }.orEmpty()
        assertTrue(files.size >= 4)
        files.forEach { SharedFixtures.element(it.name) }
    }
}
