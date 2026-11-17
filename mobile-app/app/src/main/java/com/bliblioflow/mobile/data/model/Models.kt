package com.biblioflow.mobile.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class ProfileRole {
    @SerialName("member") MEMBER,
    @SerialName("librarian") LIBRARIAN,
    @SerialName("admin") ADMIN
}

@Serializable
enum class ProfileStatus {
    @SerialName("active") ACTIVE,
    @SerialName("sanctioned") SANCTIONED,
    @SerialName("deregistered") DEREGISTERED
}

@Serializable
enum class CopyStatus {
    @SerialName("available") AVAILABLE,
    @SerialName("on_loan") ON_LOAN,
    @SerialName("reserved") RESERVED,
    @SerialName("under_repair") UNDER_REPAIR,
    @SerialName("withdrawn") WITHDRAWN
}

@Serializable
enum class LoanStatus {
    @SerialName("active") ACTIVE,
    @SerialName("overdue") OVERDUE,
    @SerialName("returned") RETURNED
}

@Serializable
enum class ReservationStatus {
    @SerialName("pending") PENDING,
    @SerialName("ready_for_pickup") READY_FOR_PICKUP,
    @SerialName("completed") COMPLETED,
    @SerialName("expired") EXPIRED,
    @SerialName("cancelled") CANCELLED
}

@Serializable
enum class SanctionStatus {
    @SerialName("active") ACTIVE,
    @SerialName("expired") EXPIRED,
    @SerialName("cancelled") CANCELLED
}

@Serializable
data class Profile(
    @SerialName("id") val id: String = "",
    @SerialName("full_name") val fullName: String? = null,
    @SerialName("email") val email: String? = null,
    @SerialName("role") val role: ProfileRole = ProfileRole.MEMBER,
    @SerialName("status") val status: ProfileStatus = ProfileStatus.ACTIVE,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null
)

@Serializable
data class Category(
    @SerialName("id") val id: String = "",
    @SerialName("name") val name: String = "",
    @SerialName("description") val description: String? = null
)

@Serializable
data class Book(
    @SerialName("id") val id: String = "",
    @SerialName("title") val title: String = "",
    @SerialName("authors") val authors: String = "",
    @SerialName("description") val description: String? = null,
    @SerialName("isbn") val isbn: String? = null,
    @SerialName("publisher") val publisher: String? = null,
    @SerialName("publication_year") val publicationYear: Int? = null,
    @SerialName("category_id") val categoryId: String? = null,
    @SerialName("language") val language: String = "es",
    @SerialName("status") val status: CopyStatus = CopyStatus.AVAILABLE,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null
)

@Serializable
data class Copy(
    @SerialName("id") val id: String = "",
    @SerialName("book_id") val bookId: String = "",
    @SerialName("status") val status: CopyStatus = CopyStatus.AVAILABLE,
    @SerialName("location_code") val locationCode: String? = null,
    @SerialName("code") val code: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null
)

@Serializable
data class Loan(
    @SerialName("id") val id: String = "",
    @SerialName("user_id") val userId: String = "",
    @SerialName("copy_id") val copyId: String = "",
    @SerialName("status") val status: LoanStatus = LoanStatus.ACTIVE,
    @SerialName("loaned_at") val loanedAt: String? = null,
    @SerialName("due_at") val dueAt: String? = null,
    @SerialName("returned_at") val returnedAt: String? = null,
    @SerialName("renewal_count") val renewalCount: Int = 0
)

@Serializable
data class Reservation(
    @SerialName("id") val id: String = "",
    @SerialName("user_id") val userId: String = "",
    @SerialName("book_id") val bookId: String = "",
    @SerialName("copy_id") val copyId: String? = null,
    @SerialName("status") val status: ReservationStatus = ReservationStatus.PENDING,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("expires_at") val expiresAt: String? = null,
    @SerialName("pickup_deadline") val pickupDeadline: String? = null
)

@Serializable
data class Sanction(
    @SerialName("id") val id: String = "",
    @SerialName("user_id") val userId: String = "",
    @SerialName("loan_id") val loanId: String = "",
    @SerialName("status") val status: SanctionStatus = SanctionStatus.ACTIVE,
    @SerialName("days") val days: Int = 0,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("expires_at") val expiresAt: String? = null
)
