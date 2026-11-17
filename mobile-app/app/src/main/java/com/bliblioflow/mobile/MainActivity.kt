package com.biblioflow.mobile

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LibraryBooks
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.biblioflow.mobile.data.model.Book
import com.biblioflow.mobile.data.model.CopyStatus
import com.biblioflow.mobile.data.repository.LibraryRepository
import com.biblioflow.mobile.ui.theme.BiblioFlowTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            BiblioFlowTheme {
                BiblioFlowApp()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BiblioFlowApp() {
    val repository = remember { LibraryRepository() }
    val profile = repository.previewProfile()
    val dashboard = repository.previewDashboard()
    val books = repository.previewBooks()
    val loans = repository.previewLoans()
    val reservations = repository.previewReservations()
    var selectedTab by rememberSaveable { mutableIntStateOf(0) }

    val tabs = listOf(
        "Overview" to Icons.Default.Home,
        "Catalog" to Icons.Default.Book,
        "Loans" to Icons.Default.LibraryBooks,
        "Profile" to Icons.Default.Person
    )

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("BiblioFlow") }
            )
        },
        bottomBar = {
            NavigationBar {
                tabs.forEachIndexed { index, (label, icon) ->
                    NavigationBarItem(
                        selected = selectedTab == index,
                        onClick = { selectedTab = index },
                        icon = { Icon(icon, contentDescription = label) },
                        label = { Text(label) }
                    )
                }
            }
        }
    ) { innerPadding ->
        when (selectedTab) {
            0 -> DashboardScreen(dashboard, innerPadding)
            1 -> CatalogScreen(books, innerPadding)
            2 -> LoansScreen(loans, reservations, innerPadding)
            3 -> ProfileScreen(profile, innerPadding)
            else -> DashboardScreen(dashboard, innerPadding)
        }
    }
}

@Composable
private fun DashboardScreen(dashboard: LibraryRepository.DashboardStats, innerPadding: PaddingValues) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(innerPadding)
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        contentPadding = PaddingValues(vertical = 16.dp)
    ) {
        item {
            HeroCard()
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                StatCard("Active loans", dashboard.activeLoans.toString(), modifier = Modifier.weight(1f))
                StatCard("Overdue", dashboard.overdueLoans.toString(), modifier = Modifier.weight(1f))
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                StatCard("Pending", dashboard.pendingReservations.toString(), modifier = Modifier.weight(1f))
                StatCard("Ready", dashboard.readyPickups.toString(), modifier = Modifier.weight(1f))
            }
        }
        item {
            StatCard("Active sanctions", dashboard.activeSanctions.toString())
        }
    }
}

@Composable
private fun HeroCard() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(180.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(
                Brush.linearGradient(
                    listOf(
                        MaterialTheme.colorScheme.primary,
                        MaterialTheme.colorScheme.secondary
                    )
                )
            )
            .padding(20.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "Welcome back",
                style = MaterialTheme.typography.titleMedium,
                color = Color.White
            )
            Text(
                text = "Your library is running smoothly.",
                style = MaterialTheme.typography.headlineSmall,
                color = Color.White,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "124 titles available • 7 reservations pending",
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.9f)
            )
        }
    }
}

@Composable
private fun CatalogScreen(books: List<Book>, innerPadding: PaddingValues) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(innerPadding)
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(vertical = 16.dp)
    ) {
        items(books) { book ->
            BookCard(book)
        }
    }
}

@Composable
private fun LoansScreen(loans: List<String>, reservations: List<String>, innerPadding: PaddingValues) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(innerPadding)
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(vertical = 16.dp)
    ) {
        item {
            Text(
                text = "My loans",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
        }
        items(loans) { loan ->
            ListRow(title = loan, subtitle = "Due in 6 days")
        }
        item { Spacer(modifier = Modifier.height(12.dp)) }
        item {
            Text(
                text = "Reservations",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
        }
        items(reservations) { reservation ->
            ListRow(title = reservation, subtitle = "Waiting for turnover")
        }
    }
}

@Composable
private fun ProfileScreen(profile: com.biblioflow.mobile.data.model.Profile, innerPadding: PaddingValues) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(innerPadding)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    profile.fullName ?: "Member",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(profile.email ?: "member@library.example", style = MaterialTheme.typography.bodyMedium)
                Text("Role: ${profile.role.name.lowercase()}", style = MaterialTheme.typography.bodyMedium)
                Text("Status: ${profile.status.name.lowercase()}", style = MaterialTheme.typography.bodyMedium)
            }
        }

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text("Permissions", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text("• View public catalog")
                Text("• Review own loans and reservations")
                Text("• Reserve books and renew eligible loans")
                Text("• Update profile full name")
            }
        }

        Button(
            onClick = { },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Sync with Supabase")
        }
    }
}

@Composable
private fun StatCard(title: String, value: String, modifier: Modifier = Modifier) {
    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun BookCard(book: Book) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(book.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(book.authors, style = MaterialTheme.typography.bodyMedium)
            if (!book.description.isNullOrBlank()) {
                Text(book.description, style = MaterialTheme.typography.bodySmall)
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("ISBN: ${book.isbn ?: "n/a"}")
                Box(
                    modifier = Modifier
                        .background(
                            when (book.status) {
                                CopyStatus.AVAILABLE -> MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                                CopyStatus.ON_LOAN -> Color(0xFFFFF3CD)
                                CopyStatus.RESERVED -> Color(0xFFDBEAFE)
                                else -> Color(0xFFF3F4F6)
                            }
                        )
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Text(
                        text = book.status.name.lowercase().replace("_", " "),
                        color = when (book.status) {
                            CopyStatus.AVAILABLE -> MaterialTheme.colorScheme.primary
                            CopyStatus.ON_LOAN -> Color(0xFF92400E)
                            CopyStatus.RESERVED -> Color(0xFF1D4ED8)
                            else -> Color(0xFF374151)
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun ListRow(title: String, subtitle: String) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                imageVector = Icons.Default.MenuBook,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(subtitle, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}
