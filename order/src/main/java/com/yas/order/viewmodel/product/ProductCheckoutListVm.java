package com.yas.order.viewmodel.product;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Builder;
import lombok.Data;

@JsonIgnoreProperties(ignoreUnknown = true)
@Builder(toBuilder = true)
@Data
public class ProductCheckoutListVm {
    Long id;
    String name;
    Double price;
    Long taxClassId;
}