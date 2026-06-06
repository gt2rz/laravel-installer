# Events & Jobs con FrankenPHP + Octane

> Patrones correctos e incorrectos. Los errores marcados no son bugs genéricos de Laravel —
> funcionan bien en PHP-FPM y rompen específicamente con Octane porque el worker persiste entre requests.

---

## Casos correctos

### 1. Evento síncrono con listener sin estado

```php
// app/Events/PingReceived.php
class PingReceived
{
    public function __construct(public readonly string $ip) {}
}

// app/Listeners/LogPing.php
class LogPing
{
    public function handle(PingReceived $event): void
    {
        Log::info('Ping from ' . $event->ip);
    }
}

// routes/api.php
Route::get('/ping', function (Request $request) {
    event(new PingReceived($request->ip()));
    return response()->json(['status' => 'ok']);
});
```

El listener no guarda estado — seguro en Octane.

---

### 2. Job asíncrono en cola

```php
// app/Jobs/ProcessPing.php
class ProcessPing implements ShouldQueue
{
    public function __construct(public readonly string $ip) {}

    public function handle(): void
    {
        Log::info('Processing ping from ' . $this->ip);
    }
}

// routes/api.php
Route::get('/ping', function (Request $request) {
    ProcessPing::dispatch($request->ip());
    return response()->json(['status' => 'ok']); // responde de inmediato
});
```

El request no espera al job. Redis recibe el job, el worker lo procesa después.

---

### 3. Listener que encola automáticamente

```php
// app/Listeners/LogPing.php
class LogPing implements ShouldQueue  // solo agregar esto
{
    public function handle(PingReceived $event): void
    {
        Http::post('https://analytics.example.com/track', ['ip' => $event->ip]);
    }
}
```

`ShouldQueue` hace que Laravel encole el listener sin cambiar el evento ni el controller.

---

### 4. Job idempotente

```php
class ProcessPing implements ShouldQueue
{
    public $tries = 3;

    public function __construct(public readonly string $ip) {}

    public function handle(): void
    {
        DB::table('pings')->updateOrInsert(
            ['ip' => $this->ip],
            ['at' => now()]
        );
    }
}
```

Si el job se reintenta tras un fallo, no genera registros duplicados.

---

### 5. Pasar solo datos primitivos al Job

```php
// Solo extraer lo necesario del Request antes de despachar
ProcessPing::dispatch($request->ip(), $request->userAgent());
```

Los jobs se serializan para guardarse en Redis — solo tipos primitivos o modelos Eloquent (que implementan `Serializable`).

---

## Casos incorrectos

### 1. Estado estático en listeners

```php
// MAL
class LogPing
{
    private static array $processed = [];

    public function handle(PingReceived $event): void
    {
        self::$processed[] = $event->ip; // crece indefinidamente
        Log::info('IPs procesadas: ' . count(self::$processed));
    }
}
```

El worker de Octane no muere entre requests. `$processed` acumula datos de todos los requests
desde que arrancó el worker. En PHP-FPM esto no pasa porque cada request es un proceso nuevo.

---

### 2. Singleton con estado mutable

```php
// MAL
class PingRepository
{
    private array $cache = [];

    public function remember(string $ip): void
    {
        $this->cache[$ip] = now();
    }
}

// AppServiceProvider
$this->app->singleton(PingRepository::class);
```

El singleton vive mientras vive el worker. El request 1000 ve la caché acumulada desde el request 1.
Usar `$this->app->bind()` en lugar de `singleton` crea una instancia nueva por request.

---

### 3. Job no idempotente con reintentos

```php
// MAL
class ProcessPing implements ShouldQueue
{
    public $tries = 3;

    public function handle(): void
    {
        DB::table('pings')->insert(['ip' => $this->ip, 'at' => now()]);
    }
}
```

Si el job falla después del `insert` (ej. timeout de red al notificar algo más),
se reintenta y duplica el registro. Con `tries=3` puedes tener hasta 3 duplicados.

---

### 4. Inyectar el objeto Request en un Job

```php
// MAL
class ProcessPing implements ShouldQueue
{
    public function __construct(private Request $request) {}
}

ProcessPing::dispatch($request); // lanza SerializationException
```

`Request` no es serializable. El dispatch explota al intentar guardar el job en Redis.

---

### 5. Listener síncrono con llamada HTTP externa

```php
// MAL
class LogPing
{
    public function handle(PingReceived $event): void
    {
        Http::post('https://analytics.example.com/track', [
            'ip' => $event->ip
        ]);
    }
}
```

El usuario espera los ~300ms (o más) que tarde la API externa. Si esa API cae,
tu endpoint `/ping` también cae. Solución: `implements ShouldQueue`.
