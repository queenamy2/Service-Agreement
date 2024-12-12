# Service Agreement Smart Contract

A robust smart contract implementation for managing service agreements between service providers and clients with built-in payment escrow, milestone tracking, and dispute resolution mechanisms.

## Features

- **Payment Escrow**: Secure handling of client payments with controlled release
- **Milestone Tracking**: Support for up to 5 service milestones with individual payment allocations
- **Dispute Resolution**: Built-in dispute filing and resolution system with administrator oversight
- **Flexible Payment Release**: Controlled release of payments based on milestone completion
- **Time-bound Agreements**: Support for agreement duration and dispute filing deadlines

## Contract Structure

### Key Components

1. **Agreement Details**
   - Service provider and client addresses
   - Total service cost
   - Agreement timeline (start and end timestamps)
   - Status tracking
   - Milestone information

2. **Payment Escrow**
   - Secure storage of client payments
   - Controlled release mechanism

3. **Dispute Management**
   - Dispute filing system
   - Resolution tracking
   - Administrator-controlled dispute settlement

### Agreement Status States

- `AWAITING_PAYMENT (0)`: Initial state after agreement creation
- `ACTIVE (1)`: Agreement is active and in progress
- `DELIVERED (2)`: All milestones completed
- `TERMINATED (3)`: Agreement terminated early
- `UNDER_DISPUTE (4)`: Dispute filed and pending resolution

## Public Functions

### For Clients

- `create-service-agreement`: Initialize a new service agreement
- `deposit-payment`: Submit payment to escrow
- `release-escrowed-payment`: Release payment to provider after service completion
- `initiate-dispute`: File a dispute
- `terminate-agreement`: End agreement (only in AWAITING_PAYMENT status)

### For Service Providers

- `mark-milestone-complete`: Mark individual milestones as completed
- `initiate-dispute`: File a dispute
- `terminate-agreement`: End agreement (only in AWAITING_PAYMENT status)

### For Administrator

- `resolve-dispute-claim`: Resolve disputes and determine payment distribution

## Error Codes

- `ERROR_UNAUTHORIZED_ACCESS (100)`: Caller not authorized
- `ERROR_INVALID_AGREEMENT_STATUS (101)`: Invalid operation for current status
- `ERROR_INSUFFICIENT_PAYMENT (102)`: Payment amount too low
- `ERROR_AGREEMENT_ALREADY_EXISTS (103)`: Duplicate agreement ID
- `ERROR_AGREEMENT_NOT_FOUND (104)`: Agreement doesn't exist
- `ERROR_INVALID_MILESTONE_INDEX (105)`: Invalid milestone reference

## Usage Example

1. Client creates agreement:
```clarity
(create-service-agreement 
    u1                          ;; agreement ID
    'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7  ;; provider address
    u1000                       ;; total cost
    u2592000                    ;; duration (30 days)
    milestones)                 ;; milestone list
```

2. Client deposits payment:
```clarity
(deposit-payment u1 u1000)      ;; full payment for agreement #1
```

3. Provider marks milestones complete:
```clarity
(mark-milestone-complete u1 u0) ;; complete first milestone
```

4. Client releases payment:
```clarity
(release-escrowed-payment u1)   ;; release payment after completion
```

## Security Considerations

- All financial transactions are escrow-protected
- Only authorized participants can interact with agreement
- Time-bound dispute filing window
- Administrator oversight for dispute resolution
- Automatic payment distribution based on dispute resolution

## Limitations

- Maximum of 5 milestones per agreement
- Dispute filing deadline is fixed at 7 days after agreement end
- No partial milestone completion tracking
- All payments must be in STX tokens

## Best Practices

1. **For Clients**:
   - Verify all milestone details before agreement creation
   - Ensure sufficient funds before creating agreement
   - Review completion evidence before releasing payment

2. **For Service Providers**:
   - Document all milestone completions thoroughly
   - Maintain clear communication with client
   - File disputes promptly if issues arise

3. **For Both Parties**:
   - Keep track of agreement deadlines
   - Document all communications and deliverables
   - Understanding dispute resolution process before entering agreement