<?php

use Illuminate\Support\Facades\Route;

use App\Http\Controllers\DashboardController;

Route::get('/ping', fn () => response()->json(['status' => 'ok', 'server' => 'frankenphp']));

Route::prefix('dashboard')->controller(DashboardController::class)->group(function () {
    Route::get('/concurrent',  'concurrent');
    Route::get('/sequential',  'sequential');
});
