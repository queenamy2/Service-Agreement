;; Service Agreement Smart Contract
;; Implements a service agreement between a service provider and client
;; with payment escrow, dispute resolution, and milestone tracking

;; Constants
(define-constant contract-administrator tx-sender)
(define-constant agreement-status-awaiting-payment u0)
(define-constant agreement-status-active u1)
(define-constant agreement-status-delivered u2)
(define-constant agreement-status-terminated u3)
(define-constant agreement-status-under-dispute u4)

;; Error constants
(define-constant ERROR_UNAUTHORIZED_ACCESS (err u100))
(define-constant ERROR_INVALID_AGREEMENT_STATUS (err u101))
(define-constant ERROR_INSUFFICIENT_PAYMENT (err u102))
(define-constant ERROR_AGREEMENT_ALREADY_EXISTS (err u103))
(define-constant ERROR_AGREEMENT_NOT_FOUND (err u104))
(define-constant ERROR_INVALID_MILESTONE_INDEX (err u105))

;; Data structures
(define-map service-agreement-details
    { agreement-identifier: uint }
    {
        service-provider-address: principal,
        client-address: principal,
        total-service-cost: uint,
        agreement-status: uint,
        agreement-start-block: uint,
        agreement-end-block: uint,
        dispute-filing-deadline-block: uint,
        service-milestones: (list 5 {
            milestone-description: (string-utf8 100),
            milestone-payment: uint,
            milestone-completed: bool
        })
    }
)

(define-map agreement-payment-escrow
    { agreement-identifier: uint }
    { escrowed-amount: uint }
)

(define-map agreement-disputes
    { agreement-identifier: uint }
    {
        dispute-reason: (string-utf8 200),
        dispute-initiator: principal,
        dispute-resolution: (optional (string-utf8 200))
    }
)

;; Read-only functions
(define-read-only (get-agreement-details (agreement-identifier uint))
    (map-get? service-agreement-details { agreement-identifier: agreement-identifier })
)

(define-read-only (get-escrowed-payment (agreement-identifier uint))
    (default-to { escrowed-amount: u0 }
        (map-get? agreement-payment-escrow { agreement-identifier: agreement-identifier })
    )
)

(define-read-only (get-dispute-details (agreement-identifier uint))
    (map-get? agreement-disputes { agreement-identifier: agreement-identifier })
)

;; Private functions
(define-private (verify-participant-authorization (agreement-identifier uint))
    (let ((agreement-info (unwrap! (get-agreement-details agreement-identifier) false)))
        (or
            (is-eq tx-sender contract-administrator)
            (is-eq tx-sender (get service-provider-address agreement-info))
            (is-eq tx-sender (get client-address agreement-info))
        )
    )
)

(define-private (milestone-completed? (milestone {
    milestone-description: (string-utf8 100),
    milestone-payment: uint,
    milestone-completed: bool
}))
    (get milestone-completed milestone))

(define-private (verify-all-milestones-complete (service-milestones (list 5 {
        milestone-description: (string-utf8 100),
        milestone-payment: uint,
        milestone-completed: bool
    })))
    (and
        (milestone-completed? (unwrap-panic (element-at service-milestones u0)))
        (milestone-completed? (unwrap-panic (element-at service-milestones u1)))
        (milestone-completed? (unwrap-panic (element-at service-milestones u2)))
        (milestone-completed? (unwrap-panic (element-at service-milestones u3)))
        (milestone-completed? (unwrap-panic (element-at service-milestones u4)))
    )
)

(define-private (update-milestone-at-index 
    (milestone {
        milestone-description: (string-utf8 100),
        milestone-payment: uint,
        milestone-completed: bool
    })
    (target-index uint)
    (index uint))
    {
        milestone-description: (get milestone-description milestone),
        milestone-payment: (get milestone-payment milestone),
        milestone-completed: (if (is-eq index target-index) 
                               true 
                               (get milestone-completed milestone))
    }
)

;; Public functions
(define-public (create-service-agreement (agreement-identifier uint) 
                                       (service-provider-address principal)
                                       (total-service-cost uint)
                                       (agreement-duration uint)
                                       (service-milestones (list 5 {
                                           milestone-description: (string-utf8 100),
                                           milestone-payment: uint,
                                           milestone-completed: bool
                                       })))
    (let ((current-block block-height))
        (asserts! (is-none (get-agreement-details agreement-identifier)) ERROR_AGREEMENT_ALREADY_EXISTS)
        (asserts! (> total-service-cost u0) ERROR_INSUFFICIENT_PAYMENT)
        
        (map-set service-agreement-details
            { agreement-identifier: agreement-identifier }
            {
                service-provider-address: service-provider-address,
                client-address: tx-sender,
                total-service-cost: total-service-cost,
                agreement-status: agreement-status-awaiting-payment,
                agreement-start-block: current-block,
                agreement-end-block: (+ current-block agreement-duration),
                dispute-filing-deadline-block: (+ (+ current-block agreement-duration) u144), ;; ~1 day after end (assuming ~10min blocks)
                service-milestones: service-milestones
            }
        )
        
        (map-set agreement-payment-escrow
            { agreement-identifier: agreement-identifier }
            { escrowed-amount: u0 }
        )
        
        (ok true)
    )
)

(define-public (deposit-payment (agreement-identifier uint) (payment-amount uint))
    (let ((agreement-info (unwrap! (get-agreement-details agreement-identifier) ERROR_AGREEMENT_NOT_FOUND))
          (current-escrow-balance (get escrowed-amount (get-escrowed-payment agreement-identifier))))
        
        (asserts! (is-eq tx-sender (get client-address agreement-info)) ERROR_UNAUTHORIZED_ACCESS)
        (asserts! (is-eq (get agreement-status agreement-info) agreement-status-awaiting-payment) ERROR_INVALID_AGREEMENT_STATUS)
        
        (try! (stx-transfer? payment-amount tx-sender (as-contract tx-sender)))
        
        (map-set agreement-payment-escrow
            { agreement-identifier: agreement-identifier }
            { escrowed-amount: (+ current-escrow-balance payment-amount) }
        )
        
        (if (>= (+ current-escrow-balance payment-amount) (get total-service-cost agreement-info))
            (map-set service-agreement-details
                { agreement-identifier: agreement-identifier }
                (merge agreement-info { agreement-status: agreement-status-active })
            )
            true
        )
        
        (ok true)
    )
)

(define-public (mark-milestone-complete (agreement-identifier uint) (milestone-index uint))
    (let ((agreement-info (unwrap! (get-agreement-details agreement-identifier) ERROR_AGREEMENT_NOT_FOUND)))
        (asserts! (is-eq tx-sender (get service-provider-address agreement-info)) ERROR_UNAUTHORIZED_ACCESS)
        (asserts! (is-eq (get agreement-status agreement-info) agreement-status-active) ERROR_INVALID_AGREEMENT_STATUS)
        (asserts! (< milestone-index (len (get service-milestones agreement-info))) ERROR_INVALID_MILESTONE_INDEX)
        
        (let ((milestones (get service-milestones agreement-info))
              (updated-service-milestones 
                (list 
                    (update-milestone-at-index (unwrap-panic (element-at milestones u0)) milestone-index u0)
                    (update-milestone-at-index (unwrap-panic (element-at milestones u1)) milestone-index u1)
                    (update-milestone-at-index (unwrap-panic (element-at milestones u2)) milestone-index u2)
                    (update-milestone-at-index (unwrap-panic (element-at milestones u3)) milestone-index u3)
                    (update-milestone-at-index (unwrap-panic (element-at milestones u4)) milestone-index u4)
                )))
            
            (map-set service-agreement-details
                { agreement-identifier: agreement-identifier }
                (merge agreement-info { service-milestones: updated-service-milestones })
            )
            
            (if (verify-all-milestones-complete updated-service-milestones)
                (map-set service-agreement-details
                    { agreement-identifier: agreement-identifier }
                    (merge agreement-info { 
                        agreement-status: agreement-status-delivered,
                        service-milestones: updated-service-milestones 
                    })
                )
                true
            )
            
            (ok true)
        )
    )
)

(define-public (release-escrowed-payment (agreement-identifier uint))
    (let ((agreement-info (unwrap! (get-agreement-details agreement-identifier) ERROR_AGREEMENT_NOT_FOUND))
          (escrow-info (get-escrowed-payment agreement-identifier)))
        
        (asserts! (is-eq tx-sender (get client-address agreement-info)) ERROR_UNAUTHORIZED_ACCESS)
        (asserts! (is-eq (get agreement-status agreement-info) agreement-status-delivered) ERROR_INVALID_AGREEMENT_STATUS)
        
        (try! (as-contract (stx-transfer? 
            (get escrowed-amount escrow-info)
            (as-contract tx-sender)
            (get service-provider-address agreement-info)
        )))
        
        (map-set agreement-payment-escrow
            { agreement-identifier: agreement-identifier }
            { escrowed-amount: u0 }
        )
        
        (ok true)
    )
)

(define-public (initiate-dispute (agreement-identifier uint) (dispute-reason (string-utf8 200)))
    (let ((agreement-info (unwrap! (get-agreement-details agreement-identifier) ERROR_AGREEMENT_NOT_FOUND)))
        (asserts! (verify-participant-authorization agreement-identifier) ERROR_UNAUTHORIZED_ACCESS)
        (asserts! (< block-height (get dispute-filing-deadline-block agreement-info)) ERROR_INVALID_AGREEMENT_STATUS)
        
        (map-set agreement-disputes
            { agreement-identifier: agreement-identifier }
            {
                dispute-reason: dispute-reason,
                dispute-initiator: tx-sender,
                dispute-resolution: none
            }
        )
        
        (map-set service-agreement-details
            { agreement-identifier: agreement-identifier }
            (merge agreement-info { agreement-status: agreement-status-under-dispute })
        )
        
        (ok true)
    )
)

(define-public (resolve-dispute-claim (agreement-identifier uint) 
                                    (resolution-details (string-utf8 200))
                                    (client-refund-percentage uint))
    (let ((agreement-info (unwrap! (get-agreement-details agreement-identifier) ERROR_AGREEMENT_NOT_FOUND))
          (escrow-info (get-escrowed-payment agreement-identifier)))
        
        (asserts! (is-eq tx-sender contract-administrator) ERROR_UNAUTHORIZED_ACCESS)
        (asserts! (is-eq (get agreement-status agreement-info) agreement-status-under-dispute) ERROR_INVALID_AGREEMENT_STATUS)
        (asserts! (<= client-refund-percentage u100) ERROR_INVALID_AGREEMENT_STATUS)
        
        (let ((client-refund-amount (/ (* (get escrowed-amount escrow-info) client-refund-percentage) u100))
              (provider-payment-amount (- (get escrowed-amount escrow-info) client-refund-amount)))
            
            ;; Process client refund
            (if (> client-refund-amount u0)
                (try! (as-contract (stx-transfer? 
                    client-refund-amount
                    (as-contract tx-sender)
                    (get client-address agreement-info)
                )))
                true
            )
            
            ;; Process provider payment
            (if (> provider-payment-amount u0)
                (try! (as-contract (stx-transfer? 
                    provider-payment-amount
                    (as-contract tx-sender)
                    (get service-provider-address agreement-info)
                )))
                true
            )
            
            ;; Update dispute resolution
            (let ((dispute-details (unwrap! (get-dispute-details agreement-identifier) ERROR_AGREEMENT_NOT_FOUND)))
                (map-set agreement-disputes
                    { agreement-identifier: agreement-identifier }
                    (merge dispute-details { dispute-resolution: (some resolution-details) })
                )
            )
            
            ;; Clear escrow and update status
            (map-set agreement-payment-escrow
                { agreement-identifier: agreement-identifier }
                { escrowed-amount: u0 }
            )
            
            (map-set service-agreement-details
                { agreement-identifier: agreement-identifier }
                (merge agreement-info { agreement-status: agreement-status-delivered })
            )
            
            (ok true)
        )
    )
)

(define-public (terminate-agreement (agreement-identifier uint))
    (let ((agreement-info (unwrap! (get-agreement-details agreement-identifier) ERROR_AGREEMENT_NOT_FOUND))
          (escrow-info (get-escrowed-payment agreement-identifier)))
        
        (asserts! (verify-participant-authorization agreement-identifier) ERROR_UNAUTHORIZED_ACCESS)
        (asserts! (is-eq (get agreement-status agreement-info) agreement-status-awaiting-payment) ERROR_INVALID_AGREEMENT_STATUS)
        
        ;; Return escrowed funds to client
        (if (> (get escrowed-amount escrow-info) u0)
            (try! (as-contract (stx-transfer? 
                (get escrowed-amount escrow-info)
                (as-contract tx-sender)
                (get client-address agreement-info)
            )))
            true
        )
        
        (map-set agreement-payment-escrow
            { agreement-identifier: agreement-identifier }
            { escrowed-amount: u0 }
        )
        
        (map-set service-agreement-details
            { agreement-identifier: agreement-identifier }
            (merge agreement-info { agreement-status: agreement-status-terminated })
        )
        
        (ok true)
    )
)