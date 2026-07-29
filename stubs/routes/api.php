<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return response()->json([
        'message' => 'Workout API Service',
    ], 200);
});

Route::get('/health', function () {
    return response()->json([
        'status' => 'up',
        'message' => 'API is healthy',
        'timestamp' => now(),
    ], 200);
});
