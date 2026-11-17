package com.biblioflow.mobile.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val DarkColorScheme = darkColorScheme(
    primary = BiblioFlowPrimary,
    secondary = BiblioFlowSecondary,
    background = BiblioFlowBackground,
    surface = BiblioFlowSurface,
    onPrimary = BiblioFlowOnPrimary,
    onSurface = BiblioFlowOnSurface
)

private val LightColorScheme = lightColorScheme(
    primary = BiblioFlowPrimary,
    secondary = BiblioFlowSecondary,
    background = BiblioFlowBackground,
    surface = BiblioFlowSurface,
    onPrimary = BiblioFlowOnPrimary,
    onSurface = BiblioFlowOnSurface
)

@Composable
fun BiblioFlowTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    MaterialTheme(
        colorScheme = colorScheme,
        content = content
    )
}
