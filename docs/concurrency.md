# Concurrencia con FrankenPHP + Octane

## El problema

Un endpoint de dashboard típico necesita datos de varias fuentes.
Sin concurrencia, las tareas corren una detrás de la otra:

```
fetchUsers()        →  80ms
fetchRecentOrders() → 120ms
calculateRevenue()  →  90ms
getSystemStats()    →  60ms
─────────────────────────────
Total               → 350ms
```

## La solución: `Octane::concurrently()`

Octane spawna las tareas en workers separados y las corre en paralelo.
El tiempo total pasa a ser el de **la tarea más lenta**, no la suma:

```
fetchUsers()        →  80ms ─┐
fetchRecentOrders() → 120ms  ├─ corren en paralelo
calculateRevenue()  →  90ms  │
getSystemStats()    →  60ms ─┘
─────────────────────────────
Total               → ~120ms  (65% más rápido)
```

## Implementación

```php
[$users, $orders, $revenue, $stats] = Octane::concurrently([
    fn () => $this->fetchUsers(),
    fn () => $this->fetchRecentOrders(),
    fn () => $this->calculateRevenue(),
    fn () => $this->getSystemStats(),
]);
```

`concurrently()` devuelve un array con los resultados en el mismo orden
que los closures — se puede desestructurar directamente.

## Endpoints de demostración

```bash
# Concurrente (~120ms)
GET /api/dashboard/concurrent

# Secuencial (~350ms) — para comparar
GET /api/dashboard/sequential
```

Respuesta de ejemplo:

```json
{
  "data": {
    "users":   { "total": 1240, "active_today": 87 },
    "orders":  { "count": 34, "pending": 5 },
    "revenue": { "today": 4320.50, "month": 98210.00 },
    "stats":   { "cache_hit_rate": "94%", "queue_size": 12 }
  },
  "elapsed_ms": 122.4,
  "mode": "concurrent"
}
```

## Por qué funciona en FrankenPHP y no en PHP-FPM

| | PHP-FPM | FrankenPHP + Octane |
|---|---|---|
| Modelo | 1 proceso por request | Workers persistentes en memoria |
| `concurrently()` | No disponible | Sí — usa los workers del pool |
| Bootstrap por request | Sí (~50ms) | No — la app ya está cargada |
| Paralelismo real | No | Sí |

En PHP-FPM cada request levanta Laravel desde cero. Octane mantiene
la aplicación en memoria y puede distribuir trabajo entre workers del pool.

## Cuándo usarlo

- Endpoints que agregan datos de múltiples tablas o servicios
- Dashboards con métricas de distintas fuentes
- Cualquier request donde las tareas son independientes entre sí

## Cuándo NO usarlo

- Tareas que dependen entre sí (task B necesita el resultado de task A)
- Writes a la misma fila en paralelo (race conditions)
- Tareas muy rápidas (<5ms) — el overhead de spawning supera la ganancia
