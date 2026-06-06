<?php

namespace App\Http\Controllers;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Laravel\Octane\Facades\Octane;

class DashboardController extends Controller
{
    /**
     * Ejecuta 4 tareas en paralelo usando workers de Octane.
     * Sin concurrencia, el tiempo total sería la suma de cada tarea.
     * Con Octane::concurrently(), el tiempo total es el de la tarea más lenta.
     */
    public function concurrent()
    {
        $start = microtime(true);

        [$users, $orders, $revenue, $stats] = Octane::concurrently([
            fn () => $this->fetchUsers(),
            fn () => $this->fetchRecentOrders(),
            fn () => $this->calculateRevenue(),
            fn () => $this->getSystemStats(),
        ]);

        return response()->json([
            'data' => compact('users', 'orders', 'revenue', 'stats'),
            'elapsed_ms' => round((microtime(true) - $start) * 1000, 2),
            'mode' => 'concurrent',
        ]);
    }

    /**
     * Las mismas 4 tareas pero secuenciales, para comparar tiempos.
     */
    public function sequential()
    {
        $start = microtime(true);

        $users   = $this->fetchUsers();
        $orders  = $this->fetchRecentOrders();
        $revenue = $this->calculateRevenue();
        $stats   = $this->getSystemStats();

        return response()->json([
            'data' => compact('users', 'orders', 'revenue', 'stats'),
            'elapsed_ms' => round((microtime(true) - $start) * 1000, 2),
            'mode' => 'sequential',
        ]);
    }

    // --- Tareas simuladas con sleep para hacer visible la diferencia ---

    private function fetchUsers(): array
    {
        usleep(80_000); // simula 80ms de query lenta
        return ['total' => 1_240, 'active_today' => 87];
    }

    private function fetchRecentOrders(): array
    {
        usleep(120_000); // simula 120ms (la tarea más lenta)
        return ['count' => 34, 'pending' => 5];
    }

    private function calculateRevenue(): array
    {
        usleep(90_000); // simula 90ms de agregación en DB
        return ['today' => 4_320.50, 'month' => 98_210.00];
    }

    private function getSystemStats(): array
    {
        usleep(60_000); // simula 60ms de llamada a Redis/cache
        return ['cache_hit_rate' => '94%', 'queue_size' => 12];
    }
}
