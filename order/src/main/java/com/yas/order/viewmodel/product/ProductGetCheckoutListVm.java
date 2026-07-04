package com.yas.order.viewmodel.product;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.util.List;

@JsonIgnoreProperties(ignoreUnknown = true)
public record ProductGetCheckoutListVm(
        List<ProductCheckoutListVm> productCheckoutListVms,
        int pageNo,
        int pageSize,
        int totalElements,
        int totalPages,
        boolean isLast
) {
}
