package com.biblioflow.mobile.data.repository

import com.biblioflow.mobile.data.SupabaseClientFactory
import com.biblioflow.mobile.data.model.Book
import com.biblioflow.mobile.data.model.Category
import com.biblioflow.mobile.data.model.CopyStatus
import com.biblioflow.mobile.data.model.Profile
import com.biblioflow.mobile.data.model.ProfileRole
import com.biblioflow.mobile.data.model.ProfileStatus
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order

class LibraryRepository(
    private val client: SupabaseClient = SupabaseClientFactory.create()
) {
    data class DashboardStats(
        val activeLoans: Int = 0,
        val overdueLoans: Int = 0,
        val pendingReservations: Int = 0,
        val readyPickups: Int = 0,
        val activeSanctions: Int = 0
    )

    suspend fun fetchProfile(): Profile? = runCatching {
        client.postgrest["profiles"]
            .select(Columns.list("*")) {
                order("full_name", Order.ASCENDING)
            }
            .decodeList<Profile>()
            .firstOrNull()
    }.getOrNull() ?: mockProfile

    suspend fun fetchCategories(): List<Category> = runCatching {
        client.postgrest["categories"]
            .select(Columns.list("*")) {
                order("name", Order.ASCENDING)
            }
            .decodeList<Category>()
    }.getOrDefault(mockCategories)

    suspend fun fetchBooks(): List<Book> = runCatching {
        client.postgrest["books"]
            .select(Columns.list("*")) {
                order("title", Order.ASCENDING)
            }
            .decodeList<Book>()
    }.getOrDefault(mockBooks)

    fun previewBooks(): List<Book> = mockBooks

    fun previewProfile(): Profile = mockProfile

    fun previewDashboard(): DashboardStats = DashboardStats(
        activeLoans = 4,
        overdueLoans = 1,
        pendingReservations = 3,
        readyPickups = 1,
        activeSanctions = 1
    )

    fun previewLoans(): List<String> = listOf(
        "The Pragmatic Programmer",
        "Clean Architecture",
        "Atomic Habits"
    )

    fun previewReservations(): List<String> = listOf(
        "Fiction & design backlog",
        "Java in Action"
    )

    companion object {
        val mockProfile = Profile(
            id = "member-demo",
            fullName = "Ana García",
            email = "ana.garcia@biblioweb.example",
            role = ProfileRole.MEMBER,
            status = ProfileStatus.ACTIVE,
            createdAt = "2026-01-10T12:00:00Z",
            updatedAt = "2026-11-17T09:45:00Z"
        )

        val mockCategories = listOf(
            Category(id = "cat-design", name = "Design", description = "UX and software design"),
            Category(id = "cat-technology", name = "Technology", description = "Programming and engineering"),
            Category(id = "cat-business", name = "Business", description = "Strategy and leadership")
        )

        val mockBooks = listOf(
            Book(
                id = "book-1",
                title = "The Pragmatic Programmer",
                authors = "Andrew Hunt, David Thomas",
                description = "A practical guide to software craftsmanship and everyday engineering decisions.",
                isbn = "9780201616224",
                publisher = "Addison-Wesley",
                publicationYear = 1999,
                categoryId = "cat-technology",
                language = "en",
                status = CopyStatus.AVAILABLE
            ),
            Book(
                id = "book-2",
                title = "Clean Architecture",
                authors = "Robert C. Martin",
                description = "Principles and practices for creating maintainable, layered software systems.",
                isbn = "9780134494166",
                publisher = "Prentice Hall",
                publicationYear = 2017,
                categoryId = "cat-technology",
                language = "en",
                status = CopyStatus.ON_LOAN
            ),
            Book(
                id = "book-3",
                title = "Atomic Habits",
                authors = "James Clear",
                description = "A simple system for improving habits and matching actions to long-term goals.",
                isbn = "9780735211292",
                publisher = "Avery",
                publicationYear = 2018,
                categoryId = "cat-business",
                language = "en",
                status = CopyStatus.RESERVED
            ),
            Book(
                id = "book-4",
                title = "The Design of Everyday Things",
                authors = "Don Norman",
                description = "Foundational reading on usability, feedback loops, and product design.",
                isbn = "9780465050659",
                publisher = "Basic Books",
                publicationYear = 2013,
                categoryId = "cat-design",
                language = "en",
                status = CopyStatus.AVAILABLE
            )
        )
    }
}
